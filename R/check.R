# avior check — the CI gate (FR-CHECK-1..4). Aggregates: lockfile drift
# against the inventory baseline, policy validity (rationale TODO, weights
# vs the static metric registry), decision completeness (review_findings),
# test-result freshness (version + environment binding, FR-TEST-2),
# excluded_but_present (PRD v1.6 A6), and unknown scope.include/exclude
# references (FR-SCAN-4). Read-only: never re-scores (FR-CHECK-4).

check_drift <- function(cfg, inventory) {
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f
  # same resolution as scan (FR-SCAN-1): renv.lock, DESCRIPTION fallback.
  # If renv.lock appeared after a DESCRIPTION-based scan, the resolved
  # source (and its hash) changes and the drift rules below fire — the
  # inventory must be regenerated from the now-authoritative lockfile.
  dep_src <- tryCatch(resolve_dep_source(cfg$root, cfg$scope$lockfile),
                      avior_error = function(e) NULL)
  if (is.null(dep_src)) {
    add(finding("-", "missing_lockfile",
                paste0("dependency source not found: ", cfg$scope$lockfile,
                       " (no DESCRIPTION fallback present)"),
                fix = "restore the lockfile or fix scope.lockfile"))
    return(findings)
  }
  if (identical(sha256_file(dep_src$file), inventory$lockfile$sha256)) {
    return(findings)
  }

  lock <- dep_src$read()
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
    # hash differs but same package set/versions (formatting, ordering, or a
    # source switch such as renv.lock replacing the DESCRIPTION fallback)
    add(finding("-", "drift_lockfile",
                "dependency source content changed since the last scan",
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

# The one row-level classification every consumer shares (writer status,
# check gate, report section 6, traceability test_status): a recorded
# test-file row is passing evidence iff nothing failed AND something
# actually passed — an all-skipped or zero-test row proves nothing.
test_row_passing <- function(r) {
  (r$failed %||% 0) == 0 && (r$passed %||% 0) > 0
}

valid_test_results <- function(x) {
  scalar_text <- function(v) {
    is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
  }
  count_ok <- function(v) {
    is.numeric(v) && length(v) == 1L && !is.na(v) && is.finite(v) &&
      v >= 0 && v == floor(v)
  }
  is.list(x) && (is.null(x$results) ||
    (is.list(x$results) && all(vapply(x$results, function(row) {
      # every count is REQUIRED and they must reconcile: a hand-edited row
      # such as {tests: 0, passed: 1} must not be able to fabricate
      # passing evidence (FR-TEST-2 — evidence is provable or invalid)
      is.list(row) && scalar_text(row$package) &&
        scalar_text(row$package_version) && scalar_text(row$file) &&
        count_ok(row$tests) && count_ok(row$passed) &&
        count_ok(row$failed) && count_ok(row$skipped) &&
        row$tests == row$passed + row$failed + row$skipped
    }, logical(1)))))
}

invalid_test_results_finding <- function() {
  finding("-", "invalid_test_results",
          "test-results.yml is not valid YAML in the expected schema",
          fix = "re-run `avior test` to regenerate test-results.yml")
}

check_test_results <- function(cfg, inventory) {
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f
  inv_versions <- stats::setNames(
    vapply(inventory$packages, function(p) p$version, character(1)),
    vapply(inventory$packages, function(p) p$name, character(1)))

  path <- file.path(cfg$paths$validation, "test-results.yml")
  results_exist <- file.exists(path)
  results <- if (results_exist) {
    tryCatch(read_yaml_file(path), error = function(e) NULL)
  } else {
    NULL
  }
  if (results_exist && !valid_test_results(results)) {
    return(list(invalid_test_results_finding()))
  }

  present <- character(0)   # packages with any recorded row
  for (r in results$results) {
    pkg <- r$package
    present <- c(present, pkg)
    # package_version semantics, not identical(): R treats `.` and `-` as
    # interchangeable separators, so an installed "3.8-6" recorded verbatim
    # must match an inventory "3.8.6" (and vice versa); a malformed version
    # fails closed as stale
    if (!same_package_version(r$package_version, unname(inv_versions[pkg]))) {
      add(finding(pkg, "stale_tests",
                  paste0("test results bound to version ", r$package_version,
                         " but the inventory has ", inv_versions[pkg]),
                  fix = "re-run `avior test` against the current environment"))
    }
    # PER ROW, mirroring the writer's own failure condition: a package with
    # one passing file must not mask a sibling all-skipped/zero-test file —
    # the recorded run as a whole was not green (FR-TEST AC)
    if ((r$failed %||% 0) > 0) {
      add(finding(pkg, "failing_tests",
                  paste0(r$failed, " targeted test(s) failing in ", r$file),
                  fix = "fix the failures, then re-run `avior test`"))
    } else if (!test_row_passing(r)) {
      add(finding(pkg, "no_passing_tests",
                  paste0(r$file, " produced no passing evidence (all ",
                         "skipped or zero tests)"),
                  fix = "make the targeted tests runnable, then re-run `avior test`"))
    }
  }
  # FR-TEST-2/A4: results must PROVE their runtime environment. "Cannot prove
  # the binding" fails closed exactly like "proven mismatch" — a missing or
  # incomplete `environment` block (old format, hand-deleted field) must not
  # sail through. Require the mapping + the three required fields, then compare.
  if (!is.null(results) && length(results$results) > 0) {
    env <- results$environment
    required <- c("lockfile_sha256", "r_version", "platform")
    missing_fields <- !is.list(env) ||
      !all(vapply(required, function(k) {
        v <- env[[k]]
        length(v) == 1 && !is.na(v) && nzchar(as.character(v))
      }, logical(1)))
    if (missing_fields) {
      add(finding("-", "missing_test_environment",
                  "test-results.yml lacks a complete environment binding (lockfile_sha256, r_version, platform) -- the run environment cannot be proven (FR-TEST-2)",
                  fix = "re-run `avior test`, which records the runtime environment"))
    } else if (!identical(env$lockfile_sha256, inventory$lockfile$sha256)) {
      add(finding("-", "stale_tests",
                  "test results were produced against a different lockfile (FR-TEST-2)",
                  fix = "re-run `avior test` in the current environment"))
    }
  }

  # every include_with_tests decision needs recorded results at all; the
  # per-row rule above already guarantees that whatever IS recorded
  # carries passing evidence
  dec_dir <- file.path(cfg$paths$validation, "decisions")
  for (f in sort_c(list.files(dec_dir, pattern = "\\.yml$", full.names = TRUE))) {
    d <- tryCatch(read_yaml_file(f), error = function(e) NULL)
    if (is.null(d) || !is.list(d) || !identical(d$decision, "include_with_tests")) next
    if (!(d$package %in% present)) {
      add(finding(d$package, "missing_test_results",
                  "include_with_tests decision but no recorded test results",
                  fix = "run `avior test` to execute and record the targeted tests"))
    }
  }
  findings
}

# A scope.include/exclude entry that names no lockfile package silently
# no-ops (typo, package since removed) — a trust defect for an audit tool
# (FR-SCAN-4). scan warns at generation time; the gate must ALSO fail on it,
# because a transient console warning is not auditable and never blocks CI.
check_scope_refs <- function(cfg, inventory) {
  findings <- list()
  # judge against the LIVE lockfile when readable (same rationale as
  # check_excluded_present): after the user fixes avior.yml or the lockfile,
  # this rule must not keep reporting a now-false fact
  present <- tryCatch(
    resolve_dep_source(cfg$root, cfg$scope$lockfile)$read()$name,
    error = function(e) vapply(inventory$packages, function(p) p$name, character(1)))
  for (field in c("include", "exclude")) {
    for (pkg in sort_c(setdiff(cfg$scope[[field]], present))) {
      findings[[length(findings) + 1L]] <- finding(
        pkg, "unknown_scope_reference",
        paste0("avior.yml scope.", field, " references a package that is ",
               "not in the lockfile"),
        fix = paste0("correct or remove `", pkg, "` in avior.yml scope.",
                     field))
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
    resolve_dep_source(cfg$root, cfg$scope$lockfile)$read()$name,
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

  # An incomplete scan (unparseable source files) is a scope gap: a package
  # referenced only there was missed. Gate on it (FR-SCAN-3 / PR #18 review).
  if (isFALSE(inventory$scan$complete)) {
    skipped <- unlist(inventory$scan$skipped_files)
    findings <- c(findings, list(finding(
      "-", "scan_incomplete",
      paste0("scan could not parse: ", paste(skipped, collapse = ", "),
             " (packages referenced only there are missing from scope)"),
      fix = "fix the parse error(s) and re-run `avior scan`, or remove the file from scope")))
  }

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
  findings <- c(findings, check_scope_refs(cfg, inventory))

  list(status = if (length(findings) == 0) "pass" else "fail",
       findings = findings)
}
