# avior assess — risk scoring through the engine adapter (FR-ASSESS-1..5)
# with the NA-cause-aware score cache (FR-X-5).
#
# Aggregation: engine metrics are "goodness" in [0,1] (riskmetric
# convention); risk = 1 - weighted.mean(goodness, policy weights).
# execution-cost metrics only run under deep = TRUE (PRD 7.2); when skipped
# they are NA with cause "execution", which never triggers cache refresh.

read_inventory <- function(cfg) {
  path <- file.path(cfg$paths$validation, "inventory.yml")
  if (!file.exists(path)) {
    avior_abort(paste0("inventory not found: ", path, " (run `avior scan` first)"))
  }
  read_yaml_file(path)
}

# FR-X-5 cause enum is network|execution: "network" = may self-heal when
# online (triggers cache refresh); "execution" = only --deep (or a code fix)
# resolves it, never auto-refreshed. A ran-but-NA offline-safe metric maps
# to "execution" for the same reason: re-assessing online won't help.
na_cause <- function(metric_id, registry) {
  if (isTRUE(registry$needs_network[registry$id == metric_id])) "network" else "execution"
}

aggregate_score <- function(values, weights, na_action, pkg) {
  v <- unlist(values)[names(weights)]
  w <- unlist(weights)
  nas <- names(weights)[is.na(v)]
  if (identical(na_action, "fail") && length(nas) > 0) {
    stop(structure(
      class = c("avior_na_error", "avior_error", "error", "condition"),
      list(message = paste0("na_action is `fail` and metrics are missing for ",
                            pkg, ": ", paste(nas, collapse = ", ")),
           call = NULL)))
  }
  if (identical(na_action, "zero")) {
    v[is.na(v)] <- 0
  }
  keep <- !is.na(v)
  if (!any(keep) || sum(w[keep]) <= 0) {
    avior_abort(paste0(
      "no effective metric weight left to score ", pkg,
      " (missing metrics or all remaining weights are zero; ",
      "check network access, run with --deep, or fix policy.weights)"))
  }
  1 - stats::weighted.mean(v[keep], w[keep])
}

risk_tier <- function(score, tiers) {
  if (score <= tiers$low_max) "low" else if (score >= tiers$high_min) "high" else "medium"
}

# Key covers the FULL policy metric set plus the deep flag, not just the
# metrics actually run: keying on run_ids alone lets a policy metric-set
# change silently reuse a stale entry that lacks the new metrics.
cache_key_path <- function(cfg, pkg, version, engine, metric_ids, deep) {
  key <- digest::digest(list(pkg = pkg, version = version,
                             engine = engine$id, engine_version = engine$version,
                             metrics = sort_c(metric_ids), deep = deep))
  file.path(cfg$paths$validation, ".cache", "scores", paste0(key, ".yml"))
}

read_score_cache <- function(path, metric_ids) {
  valid_cache_timestamp <- function(value) {
    if (!is.character(value) || length(value) != 1L || is.na(value) ||
        !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$",
               value)) {
      return(FALSE)
    }
    parsed <- suppressWarnings(as.POSIXct(
      value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
    ))
    !is.na(parsed) && identical(
      format(parsed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), value
    )
  }

  entry <- tryCatch(read_yaml_file(path), error = function(e) NULL)
  if (!is.list(entry) || !is.list(entry$metrics) ||
      length(entry$metrics) != length(metric_ids) ||
      !setequal(names(entry$metrics), metric_ids) ||
      !valid_cache_timestamp(entry$scored_at)) {
    return(NULL)
  }

  valid_metric <- function(value) {
    if (is.null(value)) return(TRUE)
    if (!is.atomic(value) || length(value) != 1L) return(FALSE)
    if (is.na(value)) return(!is.nan(value))
    is.numeric(value) && is.finite(value) && value >= 0 && value <= 1
  }
  if (!all(vapply(entry$metrics, valid_metric, logical(1)))) return(NULL)

  missing_metric <- function(value) {
    is.null(value) ||
      (length(value) == 1L && is.na(value) && !is.nan(value))
  }
  na_metric_ids <- names(entry$metrics)[
    vapply(entry$metrics, missing_metric, logical(1))
  ]

  disclosed_na <- entry$na_metrics
  valid_na_metrics <- if (length(na_metric_ids) == 0L) {
    is.null(disclosed_na) ||
      (length(disclosed_na) == 0L &&
        (is.character(disclosed_na) || is.list(disclosed_na)))
  } else {
    is.character(disclosed_na) &&
      length(disclosed_na) == length(na_metric_ids) &&
      all(!is.na(disclosed_na) & nzchar(disclosed_na)) &&
      !anyDuplicated(disclosed_na) && setequal(disclosed_na, na_metric_ids)
  }
  if (!valid_na_metrics) return(NULL)

  causes <- entry$na_causes
  valid_causes <- if (length(na_metric_ids) == 0L) {
    is.null(causes) || (is.list(causes) && length(causes) == 0L)
  } else if (is.list(causes) && length(causes) == length(na_metric_ids)) {
    cause_names <- names(causes)
    !is.null(cause_names) &&
      all(!is.na(cause_names) & nzchar(cause_names)) &&
      !anyDuplicated(cause_names) && setequal(cause_names, na_metric_ids) &&
      all(vapply(causes, function(cause) {
        is.character(cause) && length(cause) == 1L && !is.na(cause) &&
          cause %in% c("network", "execution")
      }, logical(1)))
  } else {
    FALSE
  }
  if (!valid_causes) return(NULL)
  entry
}

avior_assess <- function(root = ".", only = NULL, deep = FALSE, engine = NULL,
                         refresh_na = TRUE, network_available = TRUE) {
  cfg <- avior_config_load(root)
  inventory <- read_inventory(cfg)
  eng <- if (is.null(engine)) engine_get(cfg$policy$engine) else engine
  registry <- eng$metrics()

  weights <- cfg$policy$weights
  unknown <- setdiff(names(weights), registry$id)
  if (length(unknown) > 0) {
    avior_abort(paste0("policy.weights reference metrics not in the `",
                       eng$id, "` registry: ", paste(unknown, collapse = ", ")))
  }

  metric_ids <- names(weights)
  cost <- registry$cost[match(metric_ids, registry$id)]
  # Metrics actually run this pass: execution-tier only under --deep;
  # network-tier only when online. Excluded metrics become NA with the
  # matching cause, so offline never even asks the engine for a network
  # metric (FR-ASSESS-4) rather than merely relabelling the disclosure.
  keep <- rep(TRUE, length(metric_ids))
  if (!deep) keep <- keep & cost != "execution"
  if (!network_available) keep <- keep & cost != "network"
  run_ids <- metric_ids[keep]

  pkgs <- Filter(function(p) isTRUE(p$in_scope), inventory$packages)
  names(pkgs) <- vapply(pkgs, function(p) p$name, character(1))
  if (!is.null(only)) {
    missing <- setdiff(only, names(pkgs))
    if (length(missing) > 0) {
      avior_abort(paste0("--only names packages not in scope: ",
                         paste(missing, collapse = ", ")))
    }
  }

  scored <- list()
  all_na <- character(0)
  scored_ats <- character(0)

  for (p in pkgs) {
    cache_file <- cache_key_path(cfg, p$name, p$version, eng, metric_ids, deep)
    entry <- NULL
    force_fresh <- !is.null(only) && p$name %in% only
    if (!force_fresh && file.exists(cache_file)) {
      entry <- read_score_cache(cache_file, metric_ids)
      # improvable hit (FR-X-5): only network-cause NAs, only when online
      if (!is.null(entry) && refresh_na && network_available &&
          any(unlist(entry$na_causes) == "network")) {
        entry <- NULL
      }
    }

    if (is.null(entry)) {
      res <- eng$assess(p$name, p$version, run_ids,
                        list(deep = deep, network_available = network_available))
      # 7.2 adapter contract validation: values are goodness in [0,1] or NA
      bad <- !is.na(res$value) & (res$value < 0 | res$value > 1)
      if (any(bad)) {
        avior_abort(paste0("engine `", eng$id, "` returned values outside [0,1] for ",
                           p$name, ": ", paste(res$metric_id[bad], collapse = ", ")))
      }
      values <- stats::setNames(as.list(res$value), res$metric_id)
      values <- values[names(values) %in% metric_ids]   # ignore extraneous ids
      # policy metrics the engine did not return (or that were not run: the
      # execution tier without --deep) are NA and must be disclosed
      for (mid in setdiff(metric_ids, names(values))) values[[mid]] <- NA_real_
      values <- values[metric_ids]
      nas <- names(values)[vapply(values, is.na, logical(1))]
      entry <- list(
        package = p$name,
        version = p$version,
        metrics = values,
        na_metrics = nas,
        na_causes = stats::setNames(
          lapply(nas, function(mid) na_cause(mid, registry)), nas),
        scored_at = avior_timestamp()
      )
      dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
      write_yaml_canonical(entry, cache_file)
    }

    # round BEFORE tiering so the recorded score and its tier can never
    # contradict (0.2500049 must not read `score: 0.25, tier: medium`)
    score <- round(aggregate_score(entry$metrics, weights,
                                   cfg$policy$na_action, p$name), 4)
    pkg_out <- list(
      version = p$version,
      metrics = yaml_flow(entry$metrics[metric_ids]),
      score = score,
      tier = risk_tier(score, cfg$policy$risk_tiers)
    )
    nas <- unlist(entry$na_metrics)
    if (length(nas) > 0) pkg_out$na_metrics <- yaml_seq(sort_c(nas))
    scored[[p$name]] <- pkg_out
    all_na <- c(all_na, nas)
    scored_ats <- c(scored_ats, entry$scored_at)
  }

  scores <- list(
    avior = 1L,
    generated_by = "avior assess",
    engine = yaml_flow(list(id = eng$id, version = eng$version)),
    scored_at = if (length(scored_ats) > 0) max(scored_ats) else avior_timestamp(),
    run = yaml_flow(list(deep = deep, network = network_available)),
    packages = if (length(scored) > 0) scored[sort_c(names(scored))] else list(),
    na_metrics = yaml_seq(sort_c(unique(all_na)))
  )
  write_yaml_canonical(scores, file.path(cfg$paths$validation, "scores.yml"))
  invisible(scores)
}
