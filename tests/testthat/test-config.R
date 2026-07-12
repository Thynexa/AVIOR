# avior.yml loading + schema validation (FR-X-1, FR-INIT-1, PRD 6.2).

minimal_config <- function(...) {
  lines <- c(
    "avior: 1",
    "policy:",
    "  weights:",
    "    has_vignettes: 0.5",
    "  rationale: recorded and reviewed",
    ...
  )
  root <- tempfile("cfg-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  writeLines(lines, file.path(root, "validation", "avior.yml"))
  root
}

test_that("loads the fixture project config with fields and defaults", {
  root <- local_example_project()
  cfg <- avior_config_load(root)
  expect_s3_class(cfg, "avior_config")
  expect_identical(cfg$project$name, "minimal-example")
  expect_identical(cfg$project$validation_dir, "validation")
  expect_identical(cfg$policy$engine, "riskmetric")
  expect_identical(cfg$policy$weights[["covr_coverage"]], 2.0)
  expect_identical(cfg$policy$risk_tiers$low_max, 0.25)
  expect_identical(cfg$policy$na_action, "reweight")
  expect_identical(cfg$scope$include, "survival")
  expect_identical(cfg$scope$lockfile, "renv.lock")
  expect_false(cfg$rationale_todo)
  expect_identical(cfg$paths$validation,
                   file.path(normalizePath(root), "validation"))
  expect_identical(cfg$depth_by_risk$medium, "use_statement_required")
})

test_that("defaults are applied for omitted fields", {
  root <- minimal_config()
  cfg <- avior_config_load(root)
  expect_identical(cfg$project$validation_dir, "validation")
  expect_identical(cfg$scope$intended_for_use, "auto")
  expect_identical(cfg$scope$include, character(0))
  expect_identical(cfg$scope$exclude, character(0))
  expect_identical(cfg$scope$lockfile, "renv.lock")
  expect_identical(cfg$policy$na_action, "reweight")
  expect_identical(cfg$policy$engine, "riskmetric")
  expect_identical(cfg$policy$risk_tiers, list(low_max = 0.25, high_min = 0.55))
  expect_identical(cfg$depth_by_risk,
                   list(low = "metadata_only",
                        medium = "use_statement_required",
                        high = "targeted_tests_required"))
})

test_that("rationale TODO is flagged but does not error at load", {
  root <- minimal_config()
  cfgfile <- file.path(root, "validation", "avior.yml")
  txt <- sub("rationale: recorded and reviewed", "rationale: TODO", readLines(cfgfile))
  writeLines(txt, cfgfile)
  cfg <- avior_config_load(root)
  expect_true(cfg$rationale_todo)

  # missing rationale flags too
  writeLines(txt[!grepl("rationale", txt)], cfgfile)
  expect_true(avior_config_load(root)$rationale_todo)
})

test_that("hard schema violations raise avior_config_error", {
  expect_error(avior_config_load(tempfile("nope-")), class = "avior_config_error")

  bad <- function(...) avior_config_load(minimal_config(...))

  root <- minimal_config()
  f <- file.path(root, "validation", "avior.yml")

  writeLines(sub("avior: 1", "avior: 2", readLines(f)), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  root <- minimal_config()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(grep("avior: 1", readLines(f), invert = TRUE, value = TRUE), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  # weights: missing / empty / negative
  root <- minimal_config()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(c("avior: 1", "policy:", "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  writeLines(c("avior: 1", "policy:", "  weights: {}", "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: -1.0 }", "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  # risk tiers: low_max must be < high_min, both in (0, 1)
  expect_error(bad("policy2: x"), NA)  # unknown extra keys are tolerated
  root <- minimal_config("policy_extra: 1")
  cfg <- avior_config_load(root)
  expect_s3_class(cfg, "avior_config")

  root <- minimal_config()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: 1.0 }",
               "  risk_tiers: { low_max: 0.7, high_min: 0.5 }",
               "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")

  # na_action enum
  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: 1.0 }",
               "  na_action: ignore",
               "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")
})
