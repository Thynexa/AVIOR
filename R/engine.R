# Assessment engine adapter layer (FR-X-4, PRD 7.2).
#
# The metric registry of every adapter is STATIC — available without the
# engine package installed — because `check` must be able to validate
# policy weights offline. Only assess() needs the engine at runtime.
# Switching engines (riskmetric -> val.meter) = new adapter + re-scoring
# under the user's change control; engine id + version go into every score.

avior_engine <- function(id, version, metrics, assess) {
  if (!is.character(id) || length(id) != 1 || !nzchar(id) ||
      !is.function(metrics) || !is.function(assess)) {
    avior_abort("avior_engine: id must be a string; metrics/assess must be functions")
  }
  structure(list(id = id, version = as.character(version),
                 metrics = metrics, assess = assess),
            class = "avior_engine")
}

engines_env <- new.env(parent = emptyenv())

engine_register <- function(engine) {
  stopifnot(inherits(engine, "avior_engine"))
  assign(engine$id, engine, envir = engines_env)
  invisible(engine)
}

engine_get <- function(id) {
  if (identical(id, "riskmetric") && !exists(id, envir = engines_env)) {
    engine_register(engine_riskmetric())
  }
  if (!exists(id, envir = engines_env)) {
    avior_abort(paste0("unknown engine: `", id, "` (registered: ",
                       paste(ls(engines_env), collapse = ", "), ")"))
  }
  get(id, envir = engines_env)
}

engine_metric_registry <- function(id) engine_get(id)$metrics()

# -- riskmetric adapter -------------------------------------------------------

# Vendored registry snapshot (riskmetric is maintenance-only; ids stable).
# cost tiers per PRD 7.2: metadata = local package metadata; network = needs
# internet; execution = installs the package and runs its test suite.
riskmetric_metric_registry <- function() {
  m <- function(id, description, needs_network, cost) {
    list(id = id, description = description,
         needs_network = needs_network, cost = cost)
  }
  rows <- list(
    m("has_vignettes", "package ships vignettes", FALSE, "metadata"),
    m("has_news", "package ships a NEWS file", FALSE, "metadata"),
    m("news_current", "NEWS covers the current version", FALSE, "metadata"),
    m("has_examples", "exported functions have examples", FALSE, "metadata"),
    m("has_bug_reports_url", "DESCRIPTION declares a bug-report URL", FALSE, "metadata"),
    m("has_maintainer", "package declares a maintainer", FALSE, "metadata"),
    m("has_source_control", "DESCRIPTION links public source control", FALSE, "metadata"),
    m("has_website", "DESCRIPTION links a website", FALSE, "metadata"),
    m("exported_namespace", "namespace exports are explicit", FALSE, "metadata"),
    m("export_help", "exports are documented", FALSE, "metadata"),
    m("license", "recognised license", FALSE, "metadata"),
    m("size_codebase", "codebase size heuristic", FALSE, "metadata"),
    m("downloads_1yr", "CRAN downloads over the last year", TRUE, "network"),
    m("reverse_dependencies", "count of reverse dependencies", TRUE, "network"),
    m("dependencies", "count of dependencies", FALSE, "metadata"),
    m("last_30_bugs_status", "recent bug-report closure rate", TRUE, "network"),
    m("remote_checks", "CRAN machine check results", TRUE, "network"),
    m("covr_coverage", "unit test coverage (runs the test suite)", FALSE, "execution"),
    m("r_cmd_check", "local R CMD check (builds the package)", FALSE, "execution")
  )
  data.frame(
    id = vapply(rows, `[[`, character(1), "id"),
    description = vapply(rows, `[[`, character(1), "description"),
    needs_network = vapply(rows, `[[`, logical(1), "needs_network"),
    cost = vapply(rows, `[[`, character(1), "cost"),
    stringsAsFactors = FALSE
  )
}

riskmetric_api <- function() {
  if (!requireNamespace("riskmetric", quietly = TRUE)) {
    avior_abort(paste0(
      "the riskmetric package is not installed; install it to run ",
      "`avior assess` with the riskmetric engine"
    ))
  }
  ns <- asNamespace("riskmetric")
  list(
    pkg_ref = getExportedValue("riskmetric", "pkg_ref"),
    pkg_assess = getExportedValue("riskmetric", "pkg_assess"),
    pkg_score = getExportedValue("riskmetric", "pkg_score"),
    score_error_NA = getExportedValue("riskmetric", "score_error_NA"),
    assessment_functions = function(ids) {
      fnames <- paste0("assess_", ids)
      missing <- fnames[!vapply(
        fnames, exists, logical(1), envir = ns, inherits = FALSE
      )]
      if (length(missing)) {
        avior_abort(paste0(
          "riskmetric is missing assessment(s): ",
          paste(missing, collapse = ", ")
        ))
      }
      mget(fnames, envir = ns, inherits = FALSE)
    }
  )
}

# `diag` (optional callback) reports the RAW assessment and scored cells
# before the numeric conversion below discards their classes: a final NA
# alone cannot distinguish an errored assessment scored to a
# pkg_score_error NA from a pkg_metric_na, from scoring arithmetic that
# yields NA, or from a non-scalar scored cell the adapter converts to NA.
riskmetric_score_ref <- function(ref, metric_ids, api, diag = NULL) {
  if (!length(metric_ids)) {
    return(stats::setNames(numeric(), character()))
  }
  assessments <- api$assessment_functions(metric_ids)
  columns <- vapply(seq_along(assessments), function(i) {
    attr(assessments[[i]], "column_name") %||% metric_ids[[i]]
  }, character(1))
  names(assessments) <- columns
  assessed <- api$pkg_assess(ref, assessments = assessments)
  if (!is.null(diag)) {
    for (column in columns) {
      cell <- assessed[[column]]
      # pkg_assess on a single ref yields the raw metric at [[column]], and
      # a pkg_metric_error/condition is ITSELF list-backed — unwrapping it
      # would reduce the condition to its first field (the message string)
      # and destroy the class evidence this diagnostic exists to capture.
      # Only a bare, classless list is an outer wrapper worth unwrapping.
      raw <- if (is.list(cell) && !is.object(cell) && length(cell) > 0) {
        cell[[1]]
      } else {
        cell
      }
      note <- paste0("raw assessment ", column, ": class [",
                     paste(class(raw), collapse = "/"), "]")
      if (inherits(raw, "condition")) {
        note <- paste0(note, ", condition: ", tryCatch(
          conditionMessage(raw), error = function(e) "<unavailable>"))
      }
      diag(note)
    }
  }
  scored <- api$pkg_score(assessed, error_handler = api$score_error_NA)
  out <- stats::setNames(vapply(columns, function(column) {
    value <- suppressWarnings(as.numeric(scored[[column]]))
    if (length(value) == 1L) value else NA_real_
  }, numeric(1)), metric_ids)
  if (!is.null(diag)) {
    for (i in seq_along(columns)) {
      cell <- scored[[columns[i]]]
      diag(paste0("scored cell ", columns[i], ": class [",
                  paste(class(cell), collapse = "/"), "], length ",
                  length(unlist(cell)), ", final value ", format(out[[i]])))
    }
  }
  out
}

# R treats `.` and `-` as interchangeable package-version separators. Compare
# with package_version semantics so lockfile values such as `0.1-6` match a
# resolved `0.1.6`; malformed metadata fails closed instead of being accepted.
same_package_version <- function(actual, required) {
  tryCatch({
    actual <- base::package_version(as.character(actual))
    required <- base::package_version(as.character(required))
    isTRUE(actual == required)
  }, error = function(e) FALSE)
}

# same_package_version() fails closed, so a FALSE cannot distinguish "the
# versions differ" from "the version is unreadable". The distinction matters
# for NA causes: only a CONFIRMED mismatch may be tagged `version` (never
# self-heals online); an unreadable version must stay retryable.
known_package_version <- function(v) {
  v <- as.character(v)
  length(v) == 1 && !is.na(v) &&
    tryCatch({ base::package_version(v); TRUE }, error = function(e) FALSE)
}

# Gated diagnostics for the remote_checks containment branches (#27 root
# cause): every branch that ends in a bare NA is externally identical, so a
# spike/smoke run cannot tell a ref failure from an unreadable version from
# a scoring failure. Set AVIOR_DIAG_REMOTE=1 (the riskmetric-smoke workflow
# does) to have the adapter name the branch on stderr without touching the
# assessment result.
remote_checks_diag <- function(pkg, note) {
  if (nzchar(Sys.getenv("AVIOR_DIAG_REMOTE"))) {
    message("avior remote_checks diag [", pkg, "]: ", note)
  }
  invisible()
}

riskmetric_assess <- function(pkg, version, metric_ids, opts, api = NULL) {
  api <- api %||% riskmetric_api()
  ref <- api$pkg_ref(pkg)
  actual <- as.character(ref$version)
  # A DESCRIPTION-sourced inventory (FR-SCAN-1 fallback) pins no version:
  # the installed version is the assessment subject. Only a genuinely empty
  # requirement is unpinned — a malformed non-empty version must still fail
  # the comparison below, never silently pass.
  required <- as.character(version)
  unpinned <- length(required) != 1 || is.na(required) || !nzchar(required)
  # pkg_ref() on a package absent from the assessment library yields a ref
  # without a version; "not installed" must be named as the cause instead of
  # degrading into a mismatch message with an empty version string.
  if (length(actual) != 1 || is.na(actual) || !nzchar(actual)) {
    avior_abort(paste0(
      pkg, " is not installed in the assessment library",
      if (unpinned) "" else paste0(" (inventory requires ", version, ")")
    ))
  }
  if (!unpinned && !same_package_version(actual, required)) {
    avior_abort(paste0(
      "riskmetric resolved ", pkg, " ", actual,
      " but inventory requires ", version
    ))
  }
  # remote_checks containment compares against the effective subject: the
  # pinned version, or the installed one when the inventory pins nothing.
  target <- if (unpinned) actual else required

  values <- stats::setNames(rep(NA_real_, length(metric_ids)), metric_ids)
  causes <- stats::setNames(rep(NA_character_, length(metric_ids)), metric_ids)
  local_ids <- setdiff(metric_ids, "remote_checks")
  values[local_ids] <- riskmetric_score_ref(ref, local_ids, api)
  if ("remote_checks" %in% metric_ids) {
    remote <- tryCatch(api$pkg_ref(pkg, source = "pkg_cran_remote"),
                       error = function(e) {
                         remote_checks_diag(pkg, paste0(
                           "pkg_cran_remote ref failed: ", conditionMessage(e)))
                         NULL
                       })
    remote_version_known <- !is.null(remote) &&
      known_package_version(remote$version)
    if (!is.null(remote) && !remote_version_known) {
      remote_checks_diag(pkg, paste0(
        "remote version unreadable: ",
        paste(deparse(remote$version), collapse = " ")))
    }
    if (remote_version_known && !same_package_version(remote$version, target)) {
      # CONFIRMED containment: CRAN latest is a different release than the
      # pinned version, so its check results must not be attributed here —
      # and going online again cannot heal this NA. Cause `version` keeps it
      # out of the cache refresh rule (a retry per run would defeat the
      # cache forever); a lockfile version bump changes the cache key and
      # re-assesses naturally.
      remote_checks_diag(pkg, paste0("confirmed version mismatch: remote ",
                                     as.character(remote$version),
                                     " vs required ", target))
      causes["remote_checks"] <- "version"
    } else if (remote_version_known) {
      scoring_error <- FALSE
      diag_cb <- if (nzchar(Sys.getenv("AVIOR_DIAG_REMOTE"))) {
        function(note) remote_checks_diag(pkg, note)
      }
      values["remote_checks"] <- tryCatch(
        riskmetric_score_ref(remote, "remote_checks", api,
                             diag = diag_cb)[[1]],
        error = function(e) {
          scoring_error <<- TRUE
          remote_checks_diag(pkg, paste0("remote scoring failed: ",
                                         conditionMessage(e)))
          NA_real_
        })
      if (!is.na(values["remote_checks"])) {
        remote_checks_diag(pkg, "scored ok")
      } else if (!scoring_error) {
        # a bare final NA does NOT identify the producer — the raw
        # assessment/scored-cell diagnostics above carry the class evidence
        remote_checks_diag(
          pkg, "final scored value is NA (see raw assessment diagnostics)")
      }
    }
    # remote ref failed, or its version is unreadable so a match cannot be
    # confirmed: fail-closed NA with no cause -> the registry default
    # ("network") applies upstream and the next online run retries.
  }

  data.frame(
    metric_id = metric_ids,
    value = unname(values),
    status = ifelse(is.na(values), "na", "ok"),
    na_cause = unname(causes),
    stringsAsFactors = FALSE
  )
}

engine_riskmetric <- function() {
  version <- if (requireNamespace("riskmetric", quietly = TRUE)) {
    as.character(utils::packageVersion("riskmetric"))
  } else {
    "unavailable"
  }
  avior_engine(
    id = "riskmetric",
    version = version,
    metrics = riskmetric_metric_registry,
    assess = function(pkg, version, metric_ids, opts) {
      riskmetric_assess(pkg, version, metric_ids, opts)
    }
  )
}

# -- test/dev engine ----------------------------------------------------------

# Fixture-driven engine: `values` is pkg -> metric -> goodness (0-1).
# Metrics named in network_metrics are flagged needs_network so NA-cause
# logic can be exercised without touching the internet. `na_causes` is an
# optional pkg -> metric -> cause map for engine-attributed causes (the
# riskmetric adapter's `version` containment, PRD 7.2 / FR-X-5).
mock_engine <- function(values, id = "mock", version = "1.0",
                        network_metrics = character(0),
                        execution_metrics = character(0),
                        na_causes = NULL,
                        counter = NULL) {
  all_ids <- unique(c(unlist(lapply(values, names)), network_metrics,
                      execution_metrics))
  avior_engine(
    id = id, version = version,
    metrics = function() {
      data.frame(
        id = all_ids,
        description = paste("mock metric", all_ids),
        needs_network = all_ids %in% network_metrics,
        cost = ifelse(all_ids %in% execution_metrics, "execution",
                      ifelse(all_ids %in% network_metrics, "network", "metadata")),
        stringsAsFactors = FALSE
      )
    },
    assess = function(pkg, version, metric_ids, opts) {
      if (!is.null(counter)) {
        counter$n <- counter$n + 1L
        # record the ids and opts of each call so tests can assert, e.g.,
        # that an offline run never asks the engine for a network metric
        counter$ids <- unique(c(counter$ids, metric_ids))
        counter$last_opts <- opts
      }
      vals <- vapply(metric_ids, function(mid) {
        v <- values[[pkg]][[mid]]
        if (is.null(v)) NA_real_ else as.numeric(v)
      }, numeric(1))
      causes <- vapply(metric_ids, function(mid) {
        cv <- na_causes[[pkg]][[mid]]
        if (is.null(cv)) NA_character_ else as.character(cv)
      }, character(1))
      data.frame(
        metric_id = metric_ids,
        value = unname(vals),
        status = ifelse(is.na(vals), "na", "ok"),
        na_cause = unname(causes),
        stringsAsFactors = FALSE
      )
    }
  )
}
