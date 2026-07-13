# Regression tests for the Phase 3 adversarial review findings.

p3_metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
                "downloads_1yr", "covr_coverage", "last_30_bugs_status")
p3_vals <- function(v) stats::setNames(as.list(rep(v, length(p3_metrics))), p3_metrics)
p3_engine <- function(extra = list(), ...) {
  vals <- list(jsonlite = p3_vals(0.9), lme4 = p3_vals(0.4),
               mvtnorm = p3_vals(0.6), survival = p3_vals(0.35))
  for (pkg in names(extra)) vals[[pkg]] <- utils::modifyList(vals[[pkg]], extra[[pkg]])
  avior:::mock_engine(vals, execution_metrics = c("covr_coverage", "r_cmd_check"), ...)
}

test_that("P1: changing the policy metric set invalidates cache entries", {
  root <- local_example_project()
  avior_scan(root)
  eng <- p3_engine()
  avior_assess(root, engine = eng, deep = FALSE)   # covr cached as NA/execution

  # policy gains a second execution metric: stale entry must NOT be reused
  f <- file.path(root, "validation", "avior.yml")
  txt <- readLines(f)
  i <- grep("covr_coverage:", txt)
  txt <- append(txt, "    r_cmd_check: 1.0", after = i)
  writeLines(txt, f)

  avior_assess(root, engine = p3_engine(), deep = FALSE)
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  m <- s$packages$jsonlite$metrics
  expect_true("r_cmd_check" %in% names(m))
  expect_false("NA" %in% names(m))                      # no corrupt key
  expect_true("r_cmd_check" %in% unlist(s$packages$jsonlite$na_metrics))
  expect_true(all(c("covr_coverage", "r_cmd_check") %in% unlist(s$na_metrics)))
})

test_that("P2: a scalar decision file yields invalid_decision, not a crash", {
  root <- local_example_project()
  writeLines("include", file.path(root, "validation", "decisions", "jsonlite.yml"))
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  types <- vapply(res$findings, function(x) x$type, character(1))
  pkgs <- vapply(res$findings, function(x) x$package, character(1))
  expect_true("invalid_decision" %in% types)
  expect_true("jsonlite" %in% pkgs)
})

test_that("P3: zero in-scope packages produce a valid empty scores.yml", {
  root <- tempfile("noscope-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  writeLines('{"R": {"Version": "4.3.2"}, "Packages": {
    "MASS": {"Package": "MASS", "Version": "7.3-60", "Source": "Repository"}}}',
    file.path(root, "renv.lock"))
  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: 1.0 }", "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  avior_scan(root)
  s <- avior_assess(root, engine = p3_engine())
  expect_identical(length(s$packages), 0L)
  expect_true(file.exists(file.path(root, "validation", "scores.yml")))
})

test_that("P4: zero effective weight aborts with a classed error, not NaN", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  # all-zero weights are rejected at config load
  txt <- readLines(f)
  txt <- gsub(": (0\\.5|1\\.0|2\\.0)$", ": 0", txt)
  txt <- gsub(": (0\\.5|1\\.0|2\\.0) ", ": 0 ", txt)
  writeLines(txt, f)
  expect_error(avior_config_load(root), class = "avior_config_error")
})

test_that("P4b: reweighting down to only zero-weight metrics aborts cleanly", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  txt <- readLines(f)
  # only covr_coverage keeps weight; without --deep it is NA -> nothing left
  txt <- sub("has_vignettes: 0.5", "has_vignettes: 0", txt)
  txt <- sub("has_news: 0.5", "has_news: 0", txt)
  txt <- sub("has_bug_reports_url: 0.5", "has_bug_reports_url: 0", txt)
  txt <- sub("downloads_1yr: 1.0", "downloads_1yr: 0", txt)
  txt <- sub("last_30_bugs_status: 1.0", "last_30_bugs_status: 0", txt)
  writeLines(txt, f)
  avior_scan(root)
  expect_error(avior_assess(root, engine = p3_engine(), deep = FALSE),
               class = "avior_error")
})

test_that("P5: an in-scope package missing from scores.yml fails the gate", {
  root <- local_example_project()
  s <- file.path(root, "validation", "scores.yml")
  txt <- readLines(s)
  i <- grep("^  mvtnorm:", txt)
  j <- grep("^  survival:", txt) - 1L
  writeLines(txt[-(i:j)], s)   # drop the whole mvtnorm entry
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  types <- vapply(res$findings, function(x) x$type, character(1))
  pkgs <- vapply(res$findings, function(x) x$package, character(1))
  expect_true("unscored_package" %in% types)
  expect_true("mvtnorm" %in% pkgs)
})

test_that("P6: engine returning a metric subset still discloses the gap as NA", {
  root <- local_example_project()
  vals <- list(jsonlite = p3_vals(0.9), lme4 = p3_vals(0.4),
               mvtnorm = p3_vals(0.6), survival = p3_vals(0.35))
  vals$jsonlite$has_news <- NULL
  eng <- avior:::mock_engine(vals, execution_metrics = "covr_coverage")
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  expect_true("has_news" %in% unlist(s$packages$jsonlite$na_metrics))
})

test_that("P7: engine values outside [0,1] abort with the metric named", {
  root <- local_example_project()
  vals <- list(jsonlite = p3_vals(0.9), lme4 = p3_vals(0.4),
               mvtnorm = p3_vals(0.6), survival = p3_vals(0.35))
  vals$jsonlite$has_news <- 1.5
  eng <- avior:::mock_engine(vals, execution_metrics = "covr_coverage")
  avior_scan(root)
  expect_error(avior_assess(root, engine = eng, deep = TRUE), "has_news",
               class = "avior_error")
})

test_that("P8: --only argv hygiene mirrors --format", {
  root <- local_example_project()
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  expect_identical(suppressMessages(main(c("assess", "--only"))), 2L)
  expect_identical(suppressMessages(main(c("assess", "--only", "a",
                                           "--only", "b"))), 2L)
})

test_that("P9: excluded_but_present clears once the dep leaves the lockfile", {
  root <- local_example_project()
  f <- file.path(root, "validation", "decisions", "jsonlite.yml")
  writeLines(sub("decision: include.*", "decision: exclude", readLines(f)), f)

  # comply with the fix: remove jsonlite from renv.lock (no re-scan yet)
  lock <- file.path(root, "renv.lock")
  lockdata <- jsonlite::fromJSON(lock, simplifyVector = FALSE)
  lockdata$Packages$jsonlite <- NULL
  jsonlite::write_json(lockdata, lock, auto_unbox = TRUE)

  res <- avior_check(root)
  types <- vapply(res$findings, function(x) x$type, character(1))
  expect_false("excluded_but_present" %in% types)   # fact no longer true
  expect_true("drift_removed" %in% types)           # drift still explains it
})

test_that("P10: recorded score and tier can never contradict", {
  # risk lands at 0.2500049 unrounded; recorded 0.25 must be tier low
  vals <- list(jsonlite = list(m1 = 0.7499951))
  eng <- avior:::mock_engine(vals)
  root <- tempfile("tier-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  writeLines('{"R": {"Version": "4.3.2"}, "Packages": {
    "jsonlite": {"Package": "jsonlite", "Version": "1.8.8", "Source": "Repository"}}}',
    file.path(root, "renv.lock"))
  dir.create(file.path(root, "analysis"))
  writeLines("library(jsonlite)", file.path(root, "analysis", "main.R"))
  writeLines(c("avior: 1", "policy:",
               "  weights: { m1: 1.0 }", "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  avior_scan(root)
  avior_assess(root, engine = eng)
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  expect_identical(s$packages$jsonlite$score, 0.25)
  expect_identical(s$packages$jsonlite$tier, "low")
})

test_that("P-scan: an incomplete scan turns the check gate red", {
  root <- local_example_project()
  # a broken source file makes scan record scan.complete = FALSE
  writeLines("minqa::foo(", file.path(root, "analysis", "broken.R"))
  suppressWarnings(avior_scan(root))
  avior_assess(root, engine = p3_engine(), deep = TRUE)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  types <- vapply(res$findings, function(x) x$type, character(1))
  expect_true("scan_incomplete" %in% types)
  # and the clean fixture (complete scan) does not raise it
  clean <- local_example_project()
  expect_false("scan_incomplete" %in%
    vapply(avior_check(clean)$findings, function(x) x$type, character(1)))
})

test_that("P-cli: assess/review/check reject unknown args (exit 2)", {
  root <- local_example_project()
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  # rejection happens before the engine is touched, so no riskmetric needed
  expect_identical(suppressMessages(main(c("assess", "--bogus"))), 2L)
  expect_identical(suppressMessages(main(c("assess", "stray"))), 2L)
  expect_identical(suppressMessages(main(c("review", "--deep"))), 2L)
  expect_identical(suppressMessages(main(c("check", "--only", "x"))), 2L)
})

test_that("P-cli: review/check JSON collection fields are always arrays", {
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = p3_engine(), deep = TRUE)
  old <- setwd(root); on.exit(setwd(old), add = TRUE)

  jr <- jsonlite::fromJSON(
    paste(capture.output(main(c("review", "--format", "json"))), collapse = "\n"),
    simplifyVector = FALSE)
  expect_true(is.list(jr$stubs_created))   # [] when none, never a bare scalar
  expect_true(is.list(jr$findings))

  # break one decision so check reports exactly one finding -> still an array
  f <- file.path("validation", "decisions", "jsonlite.yml")
  writeLines(sub("rationale: .*", 'rationale: ""', readLines(f)), f)
  jc <- jsonlite::fromJSON(
    paste(capture.output(main(c("check", "--format", "json"))), collapse = "\n"),
    simplifyVector = FALSE)
  expect_true(is.list(jc$findings) && length(jc$findings) >= 1)
})

test_that("F4: offline assess never asks the engine for a network metric", {
  root <- local_example_project()
  # policy weights include a network metric (downloads_1yr) + execution covr
  counter <- new.env(); counter$n <- 0L; counter$ids <- character(0)
  eng <- avior:::mock_engine(
    list(jsonlite = p3_vals(0.9), lme4 = p3_vals(0.4),
         mvtnorm = p3_vals(0.6), survival = p3_vals(0.35)),
    network_metrics = "downloads_1yr", execution_metrics = "covr_coverage",
    counter = counter)
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE, network_available = FALSE)
  expect_false("downloads_1yr" %in% counter$ids)     # network id never requested
  expect_false(isTRUE(counter$last_opts$network_available))  # opts carries the state
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  # the excluded network metric is disclosed as NA (network cause)
  expect_true("downloads_1yr" %in% unlist(s$na_metrics))
})

test_that("F5: missing test-environment binding fails check closed", {
  root <- local_example_project()
  f <- file.path(root, "validation", "test-results.yml")
  txt <- readLines(f)
  # drop the whole environment block (lines from 'environment:' to before 'results:')
  i <- grep("^environment:", txt); j <- grep("^results:", txt) - 1L
  writeLines(txt[-(i:j)], f)
  res <- avior_check(root)
  expect_identical(res$status, "fail")
  expect_true("missing_test_environment" %in%
    vapply(res$findings, function(x) x$type, character(1)))
})

test_that("P15: --offline is recorded in the run disclosure", {
  root <- local_example_project()
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  # mock engine unavailable via CLI; use riskmetric-free path: engine param
  # not reachable from main(), so exercise the function API instead
  avior_scan(root)
  avior_assess(root, engine = p3_engine(), deep = TRUE, network_available = FALSE)
  s <- avior:::read_yaml_file(file.path("validation", "scores.yml"))
  expect_identical(s$run$network, FALSE)
})
