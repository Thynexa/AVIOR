# avior_check (FR-CHECK-1..4): drift, completeness aggregation, exit codes.
# PRD 5.7 AC: version bump / new package / blanked rationale each turn the
# gate red with the package name and a fix suggestion.

check_types <- function(res) vapply(res$findings, function(f) f$type, character(1))
check_pkgs <- function(res) vapply(res$findings, function(f) f$package, character(1))

test_that("clean fixture passes", {
  root <- local_example_project()
  res <- avior_check(root)
  expect_identical(res$status, "pass")
  expect_identical(res$findings, list())
})

test_that("AC scenario 1: bumping a package version turns drift red", {
  root <- local_example_project()
  lock <- file.path(root, "renv.lock")
  writeLines(gsub('"Version": "1.2-4"', '"Version": "1.3-0"', readLines(lock)), lock)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("drift_version" %in% check_types(res))
  expect_true("mvtnorm" %in% check_pkgs(res))
  # generic drift finding tells the user how to recover
  fixes <- unlist(lapply(res$findings, `[[`, "fix"))
  expect_true(any(grepl("avior scan", fixes)))
})

test_that("AC scenario 2: adding a package turns the gate red", {
  root <- local_example_project()
  lock <- file.path(root, "renv.lock")
  txt <- readLines(lock)
  addition <- '    "zeallot": { "Package": "zeallot", "Version": "0.1.0", "Source": "Repository", "Repository": "CRAN" },'
  i <- grep('"jsonlite":', txt)[1]
  txt <- append(txt, addition, after = i - 1)
  writeLines(txt, lock)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("drift_added" %in% check_types(res))
  expect_true("zeallot" %in% check_pkgs(res))
})

test_that("AC scenario 3: blanking a rationale turns the gate red", {
  root <- local_example_project()
  f <- file.path(root, "validation", "decisions", "jsonlite.yml")
  writeLines(sub("rationale: .*", 'rationale: ""', readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("empty_rationale" %in% check_types(res))
  expect_true("jsonlite" %in% check_pkgs(res))
})

test_that("policy rationale TODO fails the gate (FR-INIT-1)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  txt <- readLines(f)
  i <- grep("rationale:", txt)
  writeLines(c(txt[seq_len(i - 1)], "  rationale: TODO", txt[(i + 3):length(txt)]), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("policy_rationale_todo" %in% check_types(res))
})

test_that("weights referencing unregistered metrics fail offline (7.2)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("has_vignettes: 0.5", "made_up_metric: 0.5", readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("unknown_metric" %in% check_types(res))
})

test_that("excluded_but_present: exclude decision with the package still locked (A6)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "decisions", "jsonlite.yml")
  writeLines(sub("decision: include.*", "decision: exclude", readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("excluded_but_present" %in% check_types(res))
  expect_true("jsonlite" %in% check_pkgs(res))
})

test_that("stale test results: lockfile-hash binding (FR-TEST-2/A4)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  writeLines(sub("lockfile_sha256: .*", "lockfile_sha256: deadbeef", readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("stale_tests" %in% check_types(res))
})

test_that("stale test results: package version binding", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  writeLines(sub('package_version: "1.1-35.1".*', 'package_version: "1.0-0"',
                 readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("stale_tests" %in% check_types(res))
  expect_true("lme4" %in% check_pkgs(res))
})

test_that("failing targeted tests turn the gate red (FR-TEST AC)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  txt <- readLines(f)
  # keep the counts reconciled (tests == passed + failed + skipped): an
  # inconsistent row is invalid_test_results, not failing_tests
  txt <- sub("    passed: 2", "    passed: 1", txt)
  txt <- sub("    failed: 0", "    failed: 1", txt)
  writeLines(txt, f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("failing_tests" %in% check_types(res))
})

test_that("invalid test-results.yml is a structured finding", {
  bad_files <- list(
    syntax = "results: [",
    scalar = "scalar",
    row = c("results:", "  - package: jsonlite", "    file: test-json.R")
  )
  for (contents in bad_files) {
    root <- local_example_project()
    writeLines(contents, file.path(root, "validation", "test-results.yml"))
    res <- avior_check(root)
    expect_identical(res$status, "fail")
    expect_true("invalid_test_results" %in% check_types(res))
  }

  root <- local_example_project()
  writeLines("results: [", file.path(root, "validation", "test-results.yml"))
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  out <- capture.output(code <- suppressMessages(
    main(c("check", "--format", "json"))))
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"))
  expect_identical(code, 1L)
  expect_identical(parsed$status, "fail")
})

test_that("non-finite failed counts are invalid test results", {
  for (failed in c(".inf", ".nan")) {
    root <- local_example_project()
    writeLines(c(
      "results:",
      "  - package: jsonlite",
      '    package_version: "1.8.8"',
      "    file: test-json.R",
      paste0("    failed: ", failed)
    ), file.path(root, "validation", "test-results.yml"))
    res <- avior_check(root)
    expect_identical(res$status, "fail")
    expect_true("invalid_test_results" %in% check_types(res))
  }
})

test_that("negative and fractional failed counts are invalid test results", {
  for (failed in c("-1", "0.5")) {
    root <- local_example_project()
    writeLines(c(
      "results:",
      "  - package: jsonlite",
      '    package_version: "1.8.8"',
      "    file: test-json.R",
      paste0("    failed: ", failed)
    ), file.path(root, "validation", "test-results.yml"))
    res <- avior_check(root)
    expect_identical(res$status, "fail")
    expect_true("invalid_test_results" %in% check_types(res))
  }
})

test_that("CLI maps a negative failed count to validation failure", {
  root <- local_example_project()
  writeLines(c(
    "results:",
    "  - package: jsonlite",
    '    package_version: "1.8.8"',
    "    file: test-json.R",
    "    failed: -1"
  ), file.path(root, "validation", "test-results.yml"))
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  out <- capture.output(code <- suppressMessages(
    main(c("check", "--format", "json"))))
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                               simplifyVector = FALSE)
  expect_identical(code, 1L)
  expect_identical(parsed$status, "fail")
  expect_true("invalid_test_results" %in%
                vapply(parsed$findings, `[[`, character(1), "type"))
})

test_that("CLI maps a non-finite failed count to validation failure", {
  root <- local_example_project()
  writeLines(c(
    "results:",
    "  - package: jsonlite",
    '    package_version: "1.8.8"',
    "    file: test-json.R",
    "    failed: .nan"
  ), file.path(root, "validation", "test-results.yml"))
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  out <- capture.output(code <- suppressMessages(
    main(c("check", "--format", "json"))))
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                               simplifyVector = FALSE)
  expect_identical(code, 1L)
  expect_identical(parsed$status, "fail")
  expect_true("invalid_test_results" %in%
                vapply(parsed$findings, `[[`, character(1), "type"))
})

test_that("inconsistent test counts are invalid results (cannot fabricate passes)", {
  # {tests: 0, passed: 1} must not be able to forge passing evidence, and
  # rows with absent counts prove nothing either — every count is required
  # and they must reconcile (tests == passed + failed + skipped)
  bad_rows <- list(
    c("    tests: 0", "    passed: 1", "    failed: 0", "    skipped: 0"),
    c("    tests: 2", "    passed: 2", "    failed: 1", "    skipped: 0"),
    c("    passed: 1", "    failed: 0")                    # counts missing
  )
  for (row in bad_rows) {
    root <- local_example_project()
    f <- file.path(root, "validation", "test-results.yml")
    env <- readLines(f)[grep("^environment:|^  lockfile_sha256|^  r_version|^  platform", readLines(f))]
    writeLines(c(
      "avior: 1",
      env,
      "results:",
      "  - file: tests/test-lme4-fit.R",
      "    package: lme4",
      '    package_version: "1.1-35.1"',
      row
    ), f)
    res <- avior_check(root)
    expect_identical(res$status, "fail")
    expect_true("invalid_test_results" %in% check_types(res),
                label = paste(row, collapse = " "))
  }
})

test_that("unknown inventory/scores schema versions fail closed (FR-X-6)", {
  # inventory: check reports a structured finding, never interprets or crashes
  root <- local_example_project()
  f <- file.path(root, "validation", "inventory.yml")
  writeLines(sub("^avior: 1$", "avior: 2", readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("invalid_inventory" %in% check_types(res))
  # ...and command-side semantic readers refuse it as an execution error
  cfg <- avior_config_load(root)
  err <- tryCatch(avior:::read_inventory(cfg), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "schema version")

  # scores: same rule through the review_findings path
  root2 <- local_example_project()
  f2 <- file.path(root2, "validation", "scores.yml")
  writeLines(sub("^avior: 1$", "avior: 2", readLines(f2)), f2)
  res2 <- avior_check(root2)
  expect_identical(res2$status, "fail")
  expect_true("invalid_scores" %in% check_types(res2))
})

test_that("unknown test-results schema versions are invalid evidence (FR-X-6)", {
  # a future/missing schema version must not satisfy the gate, even with a
  # valid environment binding and a passing row matching the declared path
  for (version_line in list("avior: 2", "avior: 1.5", character(0))) {
    root <- local_example_project()
    f <- file.path(root, "validation", "test-results.yml")
    txt <- readLines(f)
    txt <- txt[!grepl("^avior:", txt)]
    writeLines(c(version_line, txt), f)
    res <- avior_check(root)
    expect_identical(res$status, "fail")
    expect_true("invalid_test_results" %in% check_types(res),
                label = paste("version:", paste(version_line, collapse = "")))
  }
})

test_that("passing evidence is bound to the decision's declared test files", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  # same package, same version, valid environment — but the recorded
  # passing file is NOT the one the decision declares: adding a required
  # test to the decision without re-running must not read as green
  writeLines(sub("file: tests/test-lme4-fit.R",
                 "file: tests/test-lme4-other.R", readLines(f)), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("missing_test_results" %in% check_types(res))
  msgs <- vapply(res$findings, function(x) x$message, character(1))
  expect_true(any(grepl("tests/test-lme4-fit.R", msgs, fixed = TRUE)))
})

test_that("duplicated result file paths are invalid evidence", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  txt <- readLines(f)
  # duplicate the lme4 row verbatim: the file->evidence binding becomes
  # ambiguous (a forged passing duplicate could shadow a failing row)
  start <- grep("file: tests/test-lme4-fit.R", txt)
  block <- txt[start:(start + 7)]
  block[1] <- sub("^  - ", "  - ", block[1])
  writeLines(c(txt, block), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("invalid_test_results" %in% check_types(res))
})

test_that("a passing file cannot mask a sibling all-skipped file (per-row rule)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  # append a second lme4 row that is all-skipped: the package now has one
  # green file and one non-evidence file — the run as a whole is not green
  writeLines(c(readLines(f),
    "  - file: tests/test-lme4-zzz.R",
    "    package: lme4",
    '    package_version: "1.1-35.1"',
    "    tests: 1",
    "    passed: 0",
    "    failed: 0",
    "    skipped: 1",
    "    duration_s: 0.1"
  ), f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("no_passing_tests" %in% check_types(res))
  expect_true("lme4" %in% check_pkgs(res))
  # the finding names the offending file, not just the package
  msgs <- vapply(res$findings, function(x) x$message, character(1))
  expect_true(any(grepl("test-lme4-zzz.R", msgs, fixed = TRUE)))
})

test_that("missing test results for include_with_tests packages are red", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "test-results.yml"))
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("missing_test_results" %in% check_types(res))
  expect_setequal(intersect(check_pkgs(res), c("lme4", "survival")),
                  c("lme4", "survival"))
})

test_that("missing inventory is a red finding pointing at scan", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "inventory.yml"))
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("missing_inventory" %in% check_types(res))
})

test_that("unknown scope.include references are typed findings (#24)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("include: \\[survival\\]", "include: [survival, notinlock]",
                 readLines(f)), f)
  res <- suppressWarnings(avior_check(root))
  expect_identical(res$status, "fail")
  i <- which(check_types(res) == "unknown_scope_reference")
  expect_length(i, 1L)
  expect_identical(check_pkgs(res)[i], "notinlock")
  expect_match(res$findings[[i]]$message, "scope.include", fixed = TRUE)
  expect_match(res$findings[[i]]$fix, "notinlock", fixed = TRUE)
})

test_that("unknown scope.exclude references are typed findings (#24)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("exclude: \\[\\]", "exclude: [ghostpkg]", readLines(f)), f)
  res <- suppressWarnings(avior_check(root))
  expect_identical(res$status, "fail")
  i <- which(check_types(res) == "unknown_scope_reference")
  expect_length(i, 1L)
  expect_identical(check_pkgs(res)[i], "ghostpkg")
  expect_match(res$findings[[i]]$message, "scope.exclude", fixed = TRUE)
})

test_that("unknown scope references judge the LIVE lockfile, inventory fallback (#24)", {
  # the reference is unknown to the stale inventory but present in the live
  # lockfile: the rule must not report a now-false fact
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("exclude: \\[\\]", "exclude: [zeallot]", readLines(f)), f)
  lock <- file.path(root, "renv.lock")
  txt <- readLines(lock)
  addition <- '    "zeallot": { "Package": "zeallot", "Version": "0.1.0", "Source": "Repository", "Repository": "CRAN" },'
  i <- grep('"jsonlite":', txt)[1]
  writeLines(append(txt, addition, after = i - 1), lock)
  res <- avior_check(root)   # fails on drift, but NOT on the scope reference
  expect_false("unknown_scope_reference" %in% check_types(res))

  # unreadable lockfile: fall back to the inventory baseline
  unlink(lock)
  res <- avior_check(root)
  expect_true("unknown_scope_reference" %in% check_types(res))
})

test_that("CLI: unknown scope reference fails check with exit 1 and json finding (#24)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("include: \\[survival\\]", "include: [survival, notinlock]",
                 readLines(f)), f)
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  out <- capture.output(code <- suppressMessages(suppressWarnings(
    main(c("check", "--format", "json")))))
  expect_identical(code, 1L)
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                               simplifyVector = FALSE)
  expect_identical(parsed$status, "fail")
  types <- vapply(parsed$findings, function(x) x$type, character(1))
  expect_true("unknown_scope_reference" %in% types)
  text_out <- capture.output(text_code <- suppressMessages(suppressWarnings(
    main(c("check")))), type = "message")
  expect_identical(text_code, 1L)
})

test_that("every finding names a package and carries a fix suggestion (NFR-8)", {
  root <- local_example_project()
  lock <- file.path(root, "renv.lock")
  writeLines(gsub('"Version": "1.2-4"', '"Version": "1.3-0"', readLines(lock)), lock)
  unlink(file.path(root, "validation", "decisions", "survival.yml"))
  res <- avior_check(root)
  for (f in res$findings) {
    expect_true(nzchar(f$package), label = paste("package set for", f$type))
    expect_true(!is.null(f$fix) && nzchar(f$fix),
                label = paste("fix suggestion for", f$type))
  }
})

test_that("CLI: check maps pass->0, fail->1 and emits json (FR-X-3)", {
  root <- local_example_project()
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  expect_identical(suppressMessages(main("check")), 0L)

  f <- file.path("validation", "decisions", "jsonlite.yml")
  writeLines(sub("rationale: .*", 'rationale: ""', readLines(f)), f)
  out <- capture.output(code <- suppressMessages(main(c("check", "--format", "json"))))
  expect_identical(code, 1L)
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
  expect_identical(parsed$status, "fail")
  expect_true(length(parsed$findings) >= 1)
})

# -- DESCRIPTION fallback (FR-SCAN-1, #22) ------------------------------------

test_that("check drift rules work on a DESCRIPTION-based project", {
  root <- local_description_project()
  avior_scan(root)
  res <- avior_check(root)
  # no drift and no missing-lockfile complaint right after a scan; the gate
  # may still be red for other reasons (no scores/decisions yet)
  expect_false(any(check_types(res) %in%
                   c("missing_lockfile", "drift_added", "drift_removed",
                     "drift_version", "drift_lockfile")))

  # editing DESCRIPTION moves the drift baseline
  desc <- file.path(root, "DESCRIPTION")
  writeLines(sub("Imports: jsonlite \\(>= 1.8.0\\),", "Imports: glue, jsonlite,",
                 readLines(desc)), desc)
  res <- avior_check(root)
  expect_true("drift_added" %in% check_types(res))
  expect_true("glue" %in% check_pkgs(res))
})

test_that("adding renv.lock after a DESCRIPTION scan reads as drift", {
  root <- local_description_project()
  avior_scan(root)
  writeLines(paste0(
    '{"R": {"Version": "4.3.0"}, "Packages": {',
    '"jsonlite": {"Package": "jsonlite", "Version": "1.8.8", ',
    '"Source": "Repository", "Repository": "CRAN"}}}'),
    file.path(root, "renv.lock"))
  res <- avior_check(root)
  # the now-authoritative lockfile lacks MASS/Rcpp/yaml -> drift_removed
  expect_true("drift_removed" %in% check_types(res))
  expect_true("yaml" %in% check_pkgs(res))
})

test_that("check on a missing dependency source names the fallback", {
  root <- local_description_project()
  avior_scan(root)
  unlink(file.path(root, "DESCRIPTION"))
  res <- avior_check(root)
  expect_true("missing_lockfile" %in% check_types(res))
  i <- which(check_types(res) == "missing_lockfile")
  expect_match(res$findings[[i]]$message, "DESCRIPTION", fixed = TRUE)
})
