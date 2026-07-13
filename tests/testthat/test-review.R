# avior_review (FR-REVIEW-1..5): stub generation and decision completeness
# validation. The fixture ships complete, signed decisions, so the clean
# state has zero findings; each mutation must produce exactly the expected
# finding with package name and defect type (FR-REVIEW AC).

finding_types <- function(res, pkg = NULL) {
  f <- res$findings
  if (!is.null(pkg)) f <- Filter(function(x) identical(x$package, pkg), f)
  vapply(f, function(x) x$type, character(1))
}

test_that("clean fixture: no findings, no stubs needed", {
  res <- avior_review(local_example_project())
  expect_identical(res$stubs_created, character(0))
  expect_identical(res$findings, list())
})

test_that("stub generation: missing decision gets a schema-complete stub", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "decisions", "mvtnorm.yml"))
  res <- avior_review(root)
  expect_identical(res$stubs_created, "mvtnorm")
  expect_true("missing_decision" %in% finding_types(res, "mvtnorm") ||
              "invalid_decision" %in% finding_types(res, "mvtnorm"))

  stub <- avior:::read_yaml_file(
    file.path(root, "validation", "decisions", "mvtnorm.yml"))
  expect_identical(stub$avior, 1L)
  expect_identical(stub$package, "mvtnorm")
  expect_identical(stub$version, "1.2-4")
  expect_identical(stub$score_snapshot$tier, "medium")
  expect_identical(stub$decision, "")
  expect_identical(stub$ai_assisted, FALSE)
  expect_identical(stub$assessment_type, "initial")
  expect_null(stub$supersedes)

  # stub generation is idempotent: rerun does not recreate or overwrite
  writeLines(sub('use_statement: ""', 'use_statement: "draft"',
                 readLines(file.path(root, "validation", "decisions", "mvtnorm.yml"))),
             file.path(root, "validation", "decisions", "mvtnorm.yml"))
  res2 <- avior_review(root)
  expect_identical(res2$stubs_created, character(0))
  stub2 <- avior:::read_yaml_file(
    file.path(root, "validation", "decisions", "mvtnorm.yml"))
  expect_identical(stub2$use_statement, "draft")
})

test_that("each completeness rule fires with the right package and type", {
  mutate <- function(pkg, fn) {
    root <- local_example_project()
    p <- file.path(root, "validation", "decisions", paste0(pkg, ".yml"))
    writeLines(fn(readLines(p)), p)
    avior_review(root)
  }

  # unsigned (FR-REVIEW-3)
  res <- mutate("jsonlite", function(l) sub('reviewed_by: .*', 'reviewed_by: ""', l))
  expect_identical(finding_types(res, "jsonlite"), "unsigned")

  # empty rationale
  res <- mutate("jsonlite", function(l) sub('rationale: .*', 'rationale: ""', l))
  expect_identical(finding_types(res, "jsonlite"), "empty_rationale")

  # stale score snapshot: decision version != inventory version
  res <- mutate("lme4", function(l) sub('version: "1.1-35.1"', 'version: "1.0-0"', l))
  expect_identical(finding_types(res, "lme4"), "stale_decision")

  # invalid decision enum
  res <- mutate("jsonlite", function(l) sub("decision: include.*", "decision: keep", l))
  expect_identical(finding_types(res, "jsonlite"), "invalid_decision")

  # missing use_statement on a medium/high tier package (FR-REVIEW-4);
  # the field is a `>` block scalar, so drop its continuation lines too
  res <- mutate("mvtnorm", function(l) {
    i <- grep("^use_statement:", l)
    c(l[seq_len(i - 1)], 'use_statement: ""', l[(i + 3):length(l)])
  })
  expect_identical(finding_types(res, "mvtnorm"), "missing_use_statement")

  # include_with_tests must reference at least one existing test file
  res <- mutate("lme4", function(l) sub("  - tests/test-lme4-fit.R",
                                        "  - tests/test-not-there.R", l))
  expect_identical(finding_types(res, "lme4"), "missing_tests")

  # high tier + plain include violates depth_by_risk (targeted_tests_required)
  res <- mutate("lme4", function(l) {
    l <- sub("decision: include_with_tests", "decision: include", l)
    l[!grepl("- tests/test-lme4-fit.R", l)]
  })
  expect_identical(finding_types(res, "lme4"), "depth_requires_tests")

  # ai_assisted without confirmed_by (FR-REVIEW-5)
  res <- mutate("jsonlite", function(l) sub("ai_assisted: false", "ai_assisted: true", l))
  expect_identical(finding_types(res, "jsonlite"), "unconfirmed_ai")
})

test_that("F1: a decision whose package field is wrong is rejected", {
  root <- local_example_project()
  f <- file.path(root, "validation", "decisions", "jsonlite.yml")
  writeLines(sub("package: jsonlite.*", "package: wrong-package", readLines(f)), f)
  res <- avior_review(root)
  types <- finding_types(res, "jsonlite")
  expect_true("package_mismatch" %in% types)

  # a decision missing the schema version is invalid
  writeLines(grep("^avior:", readLines(f), invert = TRUE, value = TRUE), f)
  res2 <- avior_review(root)
  expect_true("invalid_decision" %in% finding_types(res2, "jsonlite"))
})

test_that("F2: score_snapshot mismatch (engine/score/tier) is stale even at same version", {
  # engine switch: same package version, different engine -> stale_score
  root <- local_example_project()
  s <- file.path(root, "validation", "scores.yml")
  writeLines(sub('engine: \\{ id: riskmetric', 'engine: { id: other',
                 readLines(s)), s)
  res <- avior_review(root)
  expect_true("stale_score" %in% finding_types(res, "jsonlite"))

  # score change at the same engine and version -> stale_score
  root2 <- local_example_project()
  s2 <- file.path(root2, "validation", "scores.yml")
  writeLines(sub("score: 0.12", "score: 0.9", readLines(s2)), s2)
  expect_true("stale_score" %in% finding_types(avior_review(root2), "jsonlite"))

  # a consistent snapshot yields no stale_score (clean fixture)
  expect_false("stale_score" %in% finding_types(avior_review(local_example_project())))
})

test_that("F3: include_with_tests must reference an existing validation/tests/*.R", {
  mutate_tests <- function(newpath) {
    root <- local_example_project()
    f <- file.path(root, "validation", "decisions", "lme4.yml")
    writeLines(sub("  - tests/test-lme4-fit.R", paste0("  - ", newpath), readLines(f)), f)
    finding_types(avior_review(root), "lme4")
  }
  expect_true("missing_tests" %in% mutate_tests("avior.yml"))          # not under tests/
  expect_true("missing_tests" %in% mutate_tests("tests/nope.R"))       # doesn't exist
  expect_true("missing_tests" %in% mutate_tests("/etc/hosts"))         # absolute
  expect_true("missing_tests" %in% mutate_tests("tests/../avior.yml")) # traversal
  expect_true("missing_tests" %in% mutate_tests("tests/test-lme4-fit.txt")) # not .R
  # the legitimate tests/<name>.R passes (clean fixture)
  expect_false("missing_tests" %in% finding_types(avior_review(local_example_project()), "lme4"))
})

test_that("deleting a decision file is reported with the package name (AC)", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "decisions", "survival.yml"))
  # findings-only path (no stub side effects): review_findings
  cfg <- avior_config_load(root)
  f <- avior:::review_findings(cfg)
  pkgs <- vapply(f, function(x) x$package, character(1))
  expect_true("survival" %in% pkgs)
  types <- vapply(f, function(x) x$type, character(1))
  expect_true("missing_decision" %in% types)
})

test_that("review requires prior scan and assess", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "scores.yml"))
  expect_error(avior_review(root), class = "avior_error")
})
