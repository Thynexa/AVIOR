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

na_cause <- function(metric_id, registry, ran) {
  if (!ran) return("execution")
  if (isTRUE(registry$needs_network[registry$id == metric_id])) return("network")
  "metadata"
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
  if (!any(keep)) {
    avior_abort(paste0("no metric values available to score ", pkg,
                       " (check network access or run with --deep)"))
  }
  1 - stats::weighted.mean(v[keep], w[keep])
}

risk_tier <- function(score, tiers) {
  if (score <= tiers$low_max) "low" else if (score >= tiers$high_min) "high" else "medium"
}

cache_key_path <- function(cfg, pkg, version, engine, metric_ids) {
  key <- digest::digest(list(pkg = pkg, version = version,
                             engine = engine$id, engine_version = engine$version,
                             metrics = sort_c(metric_ids)))
  file.path(cfg$paths$validation, ".cache", "scores", paste0(key, ".yml"))
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
  run_ids <- if (deep) metric_ids else metric_ids[cost != "execution"]

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
    cache_file <- cache_key_path(cfg, p$name, p$version, eng, run_ids)
    entry <- NULL
    force_fresh <- !is.null(only) && p$name %in% only
    if (!force_fresh && file.exists(cache_file)) {
      entry <- read_yaml_file(cache_file)
      # improvable hit (FR-X-5): only network-cause NAs, only when online
      na_causes <- unlist(entry$na_causes)
      if (refresh_na && network_available &&
          any(na_causes == "network")) {
        entry <- NULL
      }
    }

    if (is.null(entry)) {
      res <- eng$assess(p$name, p$version, run_ids, list(deep = deep))
      values <- stats::setNames(as.list(res$value), res$metric_id)
      # metrics in the policy but not run this time (execution tier, no --deep)
      for (mid in setdiff(metric_ids, run_ids)) values[[mid]] <- NA_real_
      nas <- names(values)[vapply(values, is.na, logical(1))]
      entry <- list(
        package = p$name,
        version = p$version,
        metrics = values,
        na_metrics = nas,
        na_causes = stats::setNames(
          lapply(nas, function(mid) na_cause(mid, registry, mid %in% run_ids)),
          nas),
        scored_at = avior_timestamp()
      )
      dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
      write_yaml_canonical(entry, cache_file)
    }

    score <- aggregate_score(entry$metrics, weights, cfg$policy$na_action, p$name)
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
    packages = scored[sort_c(names(scored))],
    na_metrics = yaml_seq(sort_c(unique(all_na)))
  )
  write_yaml_canonical(scores, file.path(cfg$paths$validation, "scores.yml"))
  invisible(scores)
}
