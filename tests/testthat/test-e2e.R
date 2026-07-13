# End-to-end: the J1 journey on a fresh copy of the M0 example —
# scan -> assess (mock engine, deep) -> review -> check green; then a
# tampered state must turn the gate red (PRD 5.7 AC, 9 M2 DoD slice).

test_that("J1 pipeline runs green end-to-end on the example project", {
  metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
               "downloads_1yr", "covr_coverage", "last_30_bugs_status")
  vals <- function(v) stats::setNames(as.list(rep(v, length(metrics))), metrics)
  eng <- avior:::mock_engine(
    list(jsonlite = vals(0.9), lme4 = vals(0.4),
         mvtnorm = vals(0.6), survival = vals(0.35)),
    execution_metrics = "covr_coverage",
    network_metrics = c("downloads_1yr", "last_30_bugs_status"))

  root <- local_example_project()
  # start from inputs only: drop all generated artifacts
  unlink(file.path(root, "validation", c("inventory.yml", "scores.yml")))

  inv <- avior_scan(root)
  expect_identical(inv$summary$in_scope_assessed, 4L)

  s <- avior_assess(root, engine = eng, deep = TRUE)
  expect_identical(s$packages$survival$tier, "high")

  # the mock engine differs from the fixture's hand-authored snapshots, so a
  # faithful J1 includes the reviewer re-approving against the new assessment
  resnapshot_decisions(root)

  r <- avior_review(root)
  expect_identical(r$stubs_created, character(0))  # decisions already exist
  expect_identical(r$findings, list())

  res <- avior_check(root)
  expect_identical(res$status, "pass")

  # tamper: silently changing a decision's version must turn the gate red
  f <- file.path(root, "validation", "decisions", "survival.yml")
  writeLines(sub('version: "3.5-7"', 'version: "3.4-0"', readLines(f)), f)
  res2 <- avior_check(root)
  expect_identical(res2$status, "fail")
  types <- vapply(res2$findings, function(x) x$type, character(1))
  pkgs <- vapply(res2$findings, function(x) x$package, character(1))
  expect_true("stale_decision" %in% types)
  expect_true("survival" %in% pkgs)
})
