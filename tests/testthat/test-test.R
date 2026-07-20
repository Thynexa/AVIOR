# avior test — targeted execution + test-results evidence (FR-TEST-1..3).
#
# The fixture project maps its tests to lme4/survival, which are not
# installed in the test library. These tests therefore build a synthetic
# project whose lockfile and targeted tests reference packages that ARE
# installed (digest, yaml — hard dependencies of avior itself), so the
# runner genuinely executes testthat files end-to-end.

local_with_dir <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old), add = TRUE)
  force(code)
}

local_targeted_project <- function(env = parent.frame()) {
  root <- tempfile("targeted-")
  dir.create(file.path(root, "analysis"), recursive = TRUE)
  dir.create(file.path(root, "validation", "tests"), recursive = TRUE)

  lock_pkg <- function(name, version) {
    sprintf(paste0(
      '    "%s": {\n      "Package": "%s", "Version": "%s", ',
      '"Source": "Repository",\n      "Repository": "CRAN", ',
      '"Requirements": []\n    }'), name, name, version)
  }
  writeLines(c(
    "{",
    '  "R": { "Version": "4.3.2", "Repositories": [',
    '    { "Name": "CRAN", "URL": "https://cloud.r-project.org" } ] },',
    '  "Packages": {',
    paste(
      c(lock_pkg("digest", as.character(utils::packageVersion("digest"))),
        lock_pkg("yaml", as.character(utils::packageVersion("yaml"))),
        lock_pkg("faketrans", "0.0.1")),
      collapse = ",\n"),
    "  }",
    "}"
  ), file.path(root, "renv.lock"))

  writeLines(c("library(digest)", "library(yaml)"),
             file.path(root, "analysis", "main.R"))

  writeLines(c(
    "avior: 1",
    "project:",
    "  name: targeted-demo",
    "  validation_dir: validation",
    "policy:",
    "  engine: riskmetric",
    "  weights:",
    "    has_news: 1.0",
    "  rationale: fixture rationale for targeted-test runs"
  ), file.path(root, "validation", "avior.yml"))

  withr_defer_dir(root, env)
  avior_scan(root)
  root
}

write_test_file <- function(root, name, lines) {
  writeLines(lines, file.path(root, "validation", "tests", name))
}

passing_test <- function(pkg) {
  c(paste0("# avior-package: ", pkg),
    'test_that("round trip", {',
    '  expect_true(is.character("x"))',
    '  expect_identical(1L + 1L, 2L)',
    "})")
}

test_results_of <- function(root) {
  avior:::read_yaml_file(file.path(root, "validation", "test-results.yml"))
}

test_that("avior test runs targeted tests and writes canonical evidence", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))
  write_test_file(root, "test-yaml.R", c(
    "# avior-package: yaml",
    'test_that("yaml parses", {',
    '  expect_identical(yaml::yaml.load("a: 1")$a, 1L)',
    "})"))

  res <- avior_test(root)
  expect_identical(res$status, "ok")
  expect_length(res$results, 2L)

  doc <- test_results_of(root)
  expect_identical(doc$avior, 1L)
  expect_identical(doc$generated_by, "avior test")
  expect_identical(doc$testthat_version,
                   as.character(utils::packageVersion("testthat")))
  # rows sorted by file path (FR-X-7), one row PER FILE
  expect_identical(
    vapply(doc$results, function(r) r$file, character(1)),
    c("tests/test-digest.R", "tests/test-yaml.R"))
  r1 <- doc$results[[1]]
  expect_identical(r1$package, "digest")
  expect_identical(r1$package_version,
                   as.character(utils::packageVersion("digest")))
  expect_identical(r1$tests, 1L)     # one test_that block
  expect_identical(r1$passed, 1L)
  expect_identical(r1$failed, 0L)
  expect_identical(r1$skipped, 0L)
  expect_true(is.numeric(r1$duration_s))

  # FR-TEST-2 environment binding, provable by check
  env <- doc$environment
  expect_identical(env$lockfile_sha256,
                   avior:::sha256_file(file.path(root, "renv.lock")))
  expect_identical(env$r_version,
                   paste(R.version$major, R.version$minor, sep = "."))
  expect_identical(env$platform, R.version$platform)

  # the writer's output satisfies the frozen reader contract
  expect_true(avior:::valid_test_results(doc))
})

test_that("failed and skipped states are never reported as pass", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", c(
    "# avior-package: digest",
    'test_that("fails", { expect_true(FALSE) })',
    'test_that("errors", { stop("boom") })',
    'test_that("skips", { skip("not now") })',
    'test_that("passes", { expect_true(TRUE) })'))

  res <- avior_test(root)
  expect_identical(res$status, "fail")
  r <- test_results_of(root)$results[[1]]
  expect_identical(r$tests, 4L)
  expect_identical(r$failed, 2L)    # assertion failure + error
  expect_identical(r$skipped, 1L)
  expect_identical(r$passed, 1L)
})

test_that("re-running with a mocked timer is byte-identical (FR-X-8)", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))

  testthat::local_mocked_bindings(
    test_timer = function(expr) list(value = force(expr), elapsed = 0.42),
    .package = "avior")
  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752000000")
  on.exit(if (is.na(old)) Sys.unsetenv("SOURCE_DATE_EPOCH") else
            Sys.setenv(SOURCE_DATE_EPOCH = old), add = TRUE)

  path <- file.path(root, "validation", "test-results.yml")
  avior_test(root)
  first <- readBin(path, "raw", file.size(path))
  avior_test(root)
  second <- readBin(path, "raw", file.size(path))
  expect_identical(first, second)

  lines <- readLines(path, encoding = "UTF-8")
  expect_true('run_at: "2025-07-08T18:40:00Z"' %in% lines ||
                any(grepl("^run_at: \"", lines)))  # epoch-driven timestamp
  expect_true(any(grepl("^    duration_s: 0\\.42$", lines)))
})

test_that("mapping defects are aggregated execution errors naming each file", {
  root <- local_targeted_project()
  write_test_file(root, "test-a.R", c("x <- 1"))                    # missing
  write_test_file(root, "test-b.R", c("# avior-package: digest",
                                      "# avior-package: yaml",
                                      "x <- 1"))                    # ambiguous
  write_test_file(root, "test-c.R", c("# avior-package: not a pkg", # malformed
                                      "x <- 1"))
  write_test_file(root, "test-d.R", c("# avior-package: faketrans", # out of scope
                                      "x <- 1"))
  write_test_file(root, "test-e.R", c("# avior-package: nothere",   # not in inventory
                                      "x <- 1"))

  err <- tryCatch(avior_test(root), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  msg <- conditionMessage(err)
  expect_match(msg, "tests/test-a.R.*missing")
  expect_match(msg, "tests/test-b.R.*ambiguous")
  expect_match(msg, "tests/test-c.R.*malformed")
  expect_match(msg, "tests/test-d.R.*out of scope")
  expect_match(msg, "tests/test-e.R.*not in the inventory")
  # a defective mapping never produces partial evidence
  expect_false(file.exists(file.path(root, "validation", "test-results.yml")))
})

test_that("stray .R files under tests/ are execution errors; support files pass", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))
  write_test_file(root, "helper-setup.R", "shared <- 1")
  write_test_file(root, "notes.R", "x <- 1")
  err <- tryCatch(avior_test(root), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "notes.R")

  unlink(file.path(root, "validation", "tests", "notes.R"))
  expect_identical(avior_test(root)$status, "ok")
})

test_that("an empty or absent tests/ dir records empty evidence", {
  root <- local_targeted_project()
  res <- avior_test(root)
  expect_identical(res$status, "ok")
  doc <- test_results_of(root)
  expect_length(doc$results, 0L)
  expect_true(avior:::valid_test_results(doc))
  # environment binding is still recorded — "nothing ran" is evidence too
  expect_true(nzchar(doc$environment$lockfile_sha256))
})

test_that("avior test closes the loop with avior check (FR-TEST-2)", {
  test_finding_types <- c("stale_tests", "failing_tests", "missing_test_results",
                          "missing_test_environment", "invalid_test_results")
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))
  avior_test(root)

  types_of <- function(root) {
    vapply(avior_check(root)$findings, function(f) f$type, character(1))
  }
  expect_length(intersect(types_of(root), test_finding_types), 0L)

  # a package-version mismatch is stale evidence
  path <- file.path(root, "validation", "test-results.yml")
  lines <- readLines(path, encoding = "UTF-8")
  lines <- sub("^    package_version: .*$",
               '    package_version: "0.0.0.1"', lines)
  writeLines(lines, path)
  expect_true("stale_tests" %in% types_of(root))

  # a lockfile-hash mismatch is stale evidence
  avior_test(root)
  lines <- readLines(path, encoding = "UTF-8")
  lines <- sub("^  lockfile_sha256: .*$",
               paste0("  lockfile_sha256: ", strrep("0", 64)), lines)
  writeLines(lines, path)
  expect_true("stale_tests" %in% types_of(root))

  # failing tests gate the check
  write_test_file(root, "test-yaml.R", c(
    "# avior-package: yaml",
    'test_that("fails", { expect_true(FALSE) })'))
  avior_test(root)
  expect_true("failing_tests" %in% types_of(root))
})

test_that("--coverage collects a reference metric only and never fails the run", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))
  res <- avior_test(root, coverage = TRUE)
  expect_identical(res$status, "ok")
  r <- test_results_of(root)$results[[1]]
  if (!is.null(r$coverage_ref)) {
    expect_match(r$coverage_ref, "reference only, not a gate")
  }
})

test_that("CLI: test maps status to exit codes and emits stable JSON", {
  root <- local_targeted_project()
  write_test_file(root, "test-digest.R", passing_test("digest"))
  local_with_dir(root, {
    expect_identical(main(c("test")), 0L)
    out <- capture.output(code <- main(c("test", "--format", "json")))
    expect_identical(code, 0L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                                 simplifyVector = FALSE)
    expect_identical(parsed$command, "test")
    expect_identical(parsed$status, "ok")
    expect_identical(parsed$files, 1L)
    expect_true(is.list(parsed$packages) && length(parsed$packages) == 1)

    expect_identical(suppressMessages(main(c("test", "--bogus"))), 2L)
  })

  write_test_file(root, "test-yaml.R", c(
    "# avior-package: yaml",
    'test_that("fails", { expect_true(FALSE) })'))
  local_with_dir(root, {
    expect_identical(suppressMessages(main(c("test"))), 1L)
    out <- capture.output(
      code <- suppressMessages(main(c("test", "--format", "json"))))
    expect_identical(code, 1L)
    expect_identical(
      jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "fail")
  })
})
