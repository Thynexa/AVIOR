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
