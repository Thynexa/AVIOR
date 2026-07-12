# Static intended-for-use detection (FR-SCAN-3): library()/require()/
# requireNamespace()/loadNamespace() and pkg::/pkg::: usage, each with
# file:line provenance.

write_source <- function(files) {
  root <- tempfile("src-")
  for (name in names(files)) {
    p <- file.path(root, name)
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(files[[name]], p)
  }
  root
}

test_that("detects every call form with file:line provenance", {
  root <- write_source(list(
    "analysis/main.R" = c(
      "library(lme4)",                       # line 1
      "require('survival')",                 # line 2
      "x <- 1",
      'requireNamespace("jsonlite", quietly = TRUE)',  # line 4
      "loadNamespace('mvtnorm')",            # line 5
      "y <- digest::digest(x)",              # line 6
      "z <- utils:::head(x)"                 # line 7
    )
  ))
  calls <- avior:::scan_direct_calls(root)
  expect_setequal(calls$package,
                  c("lme4", "survival", "jsonlite", "mvtnorm", "digest", "utils"))
  expect_identical(calls$file[calls$package == "lme4"], "analysis/main.R")
  expect_identical(calls$line[calls$package == "lme4"], 1L)
  expect_identical(calls$line[calls$package == "digest"], 6L)
  expect_identical(calls$line[calls$package == "utils"], 7L)
})

test_that("records first occurrence only, in C-locale file order then line", {
  root <- write_source(list(
    "b.R" = "library(jsonlite)",
    "a.R" = c("x <- 1", "jsonlite::toJSON(x)")
  ))
  calls <- avior:::scan_direct_calls(root)
  expect_identical(nrow(calls), 1L)
  expect_identical(calls$file, "a.R")   # a.R sorts before b.R
  expect_identical(calls$line, 2L)
})

test_that("skips computed/non-literal arguments and records nothing for them", {
  root <- write_source(list(
    "dyn.R" = c(
      "pkg <- 'jsonlite'",
      "library(pkg, character.only = TRUE)",  # computed: cannot resolve statically
      "do.call(library, list('yaml'))"
    )
  ))
  calls <- avior:::scan_direct_calls(root)
  # `library(pkg, character.only = TRUE)` names the SYMBOL pkg, not a package;
  # character.only = TRUE means the symbol is a variable -> must be skipped.
  expect_false("pkg" %in% calls$package)
  expect_false("yaml" %in% calls$package)
})

test_that("unparseable files are skipped with a warning and recorded", {
  root <- write_source(list(
    "ok.R" = "library(jsonlite)",
    "broken.R" = "if (TRUE { 'syntax error'"
  ))
  expect_warning(calls <- avior:::scan_direct_calls(root), "broken.R")
  expect_identical(calls$package, "jsonlite")
  expect_identical(attr(calls, "skipped"), "broken.R")
})

test_that("excludes the validation dir and renv infrastructure", {
  root <- write_source(list(
    "analysis/main.R" = "library(jsonlite)",
    "validation/tests/test-x.R" = "library(survival)",
    "renv/activate.R" = "library(yaml)"
  ))
  calls <- avior:::scan_direct_calls(root, exclude_dirs = c("validation", "renv"))
  expect_identical(calls$package, "jsonlite")
})

test_that("fixture project detection matches its inventory provenance", {
  root <- local_example_project()
  calls <- avior:::scan_direct_calls(root, exclude_dirs = c("validation", "renv"))
  expect_setequal(calls$package, c("jsonlite", "lme4", "mvtnorm", "survival"))
  main <- "analysis/main.R"
  expect_identical(unique(calls$file), main)
  # provenance lines recorded in the hand-built inventory.yml
  expect_identical(calls$line[calls$package == "lme4"], 2L)
  expect_identical(calls$line[calls$package == "survival"], 3L)
  expect_identical(calls$line[calls$package == "jsonlite"], 14L)
  expect_identical(calls$line[calls$package == "mvtnorm"], 18L)
})

test_that("deterministic across repeated runs", {
  root <- local_example_project()
  a <- avior:::scan_direct_calls(root, exclude_dirs = c("validation", "renv"))
  b <- avior:::scan_direct_calls(root, exclude_dirs = c("validation", "renv"))
  expect_identical(a, b)
})
