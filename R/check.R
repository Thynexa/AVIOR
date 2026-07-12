# avior check — the CI gate (FR-CHECK-1..4). Aggregates: lockfile drift
# against the inventory baseline, policy validity (rationale TODO, weights
# vs the static metric registry), decision completeness (review_findings),
# test-result freshness (version + environment binding, FR-TEST-2), and
# excluded_but_present (PRD v1.6 A6). Read-only: never re-scores (FR-CHECK-4).

check_drift <- function(cfg, inventory) {
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f
  lock_path <- file.path(cfg$root, cfg$scope$lockfile)
  if (!file.exists(lock_path)) {
    add(finding("-", "missing_lockfile",
                paste0("lockfile not found: ", cfg$scope$lockfile),
                fix = "restore the lockfile or fix scope.lockfile"))
    return(findings)
  }
  if (identical(sha256_file(lock_path), inventory$lockfile$sha256)) {
    return(findings)
  }

  lock <- read_renv_lock(lock_path)
  inv_names <- vapply(inventory$packages, function(p) p$name, character(1))
  inv_versions <- stats::setNames(
    vapply(inventory$packages, function(p) p$version, character(1)), inv_names)

  for (pkg in sort_c(setdiff(lock$name, inv_names))) {
    add(finding(pkg, "drift_added",
                "package present in the lockfile but not in the inventory",
                fix = "run `avior scan`, then `avior assess` and `avior review` for it"))
  }
  for (pkg in sort_c(setdiff(inv_names, lock$name))) {
    add(finding(pkg, "drift_removed",
                "package in the inventory but no longer in the lockfile",
                fix = "run `avior scan` to refresh the inventory"))
  }
  for (pkg in sort_c(intersect(lock$name, inv_names))) {
    lv <- lock$version[lock$name == pkg]
    if (!identical(lv, unname(inv_versions[pkg]))) {
      add(finding(pkg, "drift_version",
                  paste0("version changed: inventory ", inv_versions[pkg],
                         " vs lockfile ", lv),
                  fix = "run `avior scan` and re-assess/re-review the package"))
    }
  }
  if (length(findings) == 0) {
    # hash differs but same package set/versions (formatting, ordering, ...)
    add(finding("-", "drift_lockfile",
                "lockfile content changed since the last scan",
                fix = "run `avior scan` to refresh the drift baseline"))
  }
  findings
}

check_policy <- function(cfg) {
  findings <- list()
  if (isTRUE(cfg$rationale_todo)) {
    findings[[length(findings) + 1L]] <- finding(
      "-", "policy_rationale_todo",
      "policy.rationale is missing or still TODO (FR-INIT-1)",
      fix = "record the organisation's rationale for weights and thresholds in avior.yml")
  }
  registry <- tryCatch(engine_metric_registry(cfg$policy$engine),
                       avior_error = function(e) NULL)
  if (is.null(registry)) {
    findings[[length(findings) + 1L]] <- finding(
      "-", "unknown_engine",
      paste0("policy.engine `", cfg$policy$engine, "` has no registered adapter"),
      fix = "use a registered engine id (e.g. riskmetric)")
  } else {
    unknown <- setdiff(names(cfg$policy$weights), registry$id)
    for (m in sort_c(unknown)) {
      findings[[length(findings) + 1L]] <- finding(
        "-", "unknown_metric",
        paste0("policy.weights references unregistered metric `", m, "`"),
        fix = paste0("use metric ids from the ", cfg$policy$engine, " registry"))
    }
  }
  findings
}

check_test_results <- function(cfg, inventory) {
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f
  inv_versions <- stats::setNames(
    vapply(inventory$packages, function(p) p$version, character(1)),
    vapply(inventory$packages, function(p) p$name, character(1)))

  path <- file.path(cfg$paths$validation, "test-results.yml")
  results <- if (file.exists(path)) read_yaml_file(path) else NULL

  tested <- character(0)
  for (r in results$results) {
    pkg <- r$package
    tested <- c(tested, pkg)
    if (!identical(r$package_version, unname(inv_versions[pkg]))) {
      add(finding(pkg, "stale_tests",
                  paste0("test results bound to version ", r$package_version,
                         " but the inventory has ", inv_versions[pkg]),
                  fix = "re-run `avior test` against the current environment"))
    }
    if ((r$failed %||% 0) > 0) {
      add(finding(pkg, "failing_tests",
                  paste0(r$failed, " targeted test(s) failing in ", r$file),
                  fix = "fix the failures, then re-run `avior test`"))
    }
  }
  if (!is.null(results)) {
    env_sha <- results$environment$lockfile_sha256
    if (!is.null(env_sha) && !identical(env_sha, inventory$lockfile$sha256)) {
      add(finding("-", "stale_tests",
                  "test results were produced against a different lockfile (FR-TEST-2)",
                  fix = "re-run `avior test` in the current environment"))
    }
  }

  # every include_with_tests decision needs current results
  dec_dir <- file.path(cfg$paths$validation, "decisions")
  for (f in sort_c(list.files(dec_dir, pattern = "\\.yml$", full.names = TRUE))) {
    d <- tryCatch(read_yaml_file(f), error = function(e) NULL)
    if (is.null(d) || !is.list(d) || !identical(d$decision, "include_with_tests")) next
    if (!(d$package %in% tested)) {
      add(finding(d$package, "missing_test_results",
                  "include_with_tests decision but no recorded test results",
                  fix = "run `avior test` to execute and record the targeted tests"))
    }
  }
  findings
}

check_excluded_present <- function(cfg, inventory) {
  findings <- list()
  # judge against the LIVE lockfile when readable: after the user removes
  # the dependency (the suggested fix) but before a re-scan, this rule must
  # not keep reporting a now-false fact; the stale inventory is the fallback
  present <- tryCatch(
    read_renv_lock(file.path(cfg$root, cfg$scope$lockfile))$name,
    error = function(e) vapply(inventory$packages, function(p) p$name, character(1)))
  dec_dir <- file.path(cfg$paths$validation, "decisions")
  for (f in sort_c(list.files(dec_dir, pattern = "\\.yml$", full.names = TRUE))) {
    d <- tryCatch(read_yaml_file(f), error = function(e) NULL)
    if (is.null(d) || !is.list(d) || !identical(d$decision, "exclude")) next
    if (d$package %in% present) {
      findings[[length(findings) + 1L]] <- finding(
        d$package, "excluded_but_present",
        "decision is `exclude` but the package is still in the lockfile (A6)",
        fix = "remove the dependency from the project, or revise the decision with rationale")
    }
  }
  findings
}

avior_check <- function(root = ".") {
  cfg <- avior_config_load(root)
  findings <- check_policy(cfg)

  inv_path <- file.path(cfg$paths$validation, "inventory.yml")
  if (!file.exists(inv_path)) {
    findings <- c(findings, list(finding(
      "-", "missing_inventory",
      "no inventory baseline (validation/inventory.yml)",
      fix = "run `avior scan` first")))
    return(list(status = "fail", findings = findings))
  }
  inventory <- read_yaml_file(inv_path)

  findings <- c(findings, check_drift(cfg, inventory))

  scores_available <- file.exists(file.path(cfg$paths$validation, "scores.yml"))
  if (scores_available) {
    findings <- c(findings, review_findings(cfg, inventory))
  } else if (length(in_scope_packages(inventory)) > 0) {
    findings <- c(findings, list(finding(
      "-", "missing_scores",
      "in-scope packages but no scores (validation/scores.yml)",
      fix = "run `avior assess` first")))
  }

  findings <- c(findings, check_test_results(cfg, inventory))
  findings <- c(findings, check_excluded_present(cfg, inventory))

  list(status = if (length(findings) == 0) "pass" else "fail",
       findings = findings)
}
