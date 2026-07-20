# avior bundle — the evidence compiler (FR-BUNDLE-1,2,4..8).

# Fixture project brought to a check-green state (J1 shape from test-e2e):
# scan -> assess with a mock engine -> reviewer re-approves snapshots.
local_checked_project <- function(env = parent.frame()) {
  metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
               "downloads_1yr", "covr_coverage", "last_30_bugs_status")
  vals <- function(v) stats::setNames(as.list(rep(v, length(metrics))), metrics)
  eng <- avior:::mock_engine(
    list(jsonlite = vals(0.9), lme4 = vals(0.4),
         mvtnorm = vals(0.6), survival = vals(0.35)),
    execution_metrics = "covr_coverage",
    network_metrics = c("downloads_1yr", "last_30_bugs_status"))

  root <- local_example_project(env)
  unlink(file.path(root, "validation", c("inventory.yml", "scores.yml")))
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)
  resnapshot_decisions(root)
  stopifnot(identical(avior_check(root)$status, "pass"))
  root
}

fixed_session <- function() {
  list(
    r_version = "4.3.2",
    platform = "x86_64-pc-linux-gnu",
    lc_collate = "C",
    blas = "reference BLAS (libRblas, bundled with R)",
    lapack = "LAPACK 3.11.0 (libRlapack, bundled with R)",
    session_text = "R version 4.3.2 (mocked session info)"
  )
}

local_bundle_env <- function(epoch = "1752000000", env = parent.frame()) {
  testthat::local_mocked_bindings(capture_session = fixed_session,
                                  .package = "avior", .env = env)
  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = epoch)
  do.call(on.exit, list(bquote(
    if (is.na(.(old))) Sys.unsetenv("SOURCE_DATE_EPOCH") else
      Sys.setenv(SOURCE_DATE_EPOCH = .(old))
  ), add = TRUE), envir = env)
}

test_that("a passing project compiles a complete, self-verifying bundle", {
  local_bundle_env()
  root <- local_checked_project()

  res <- avior_bundle(root)
  expect_identical(res$status, "ok")
  expect_identical(res$integrity_check, "passed")
  expect_false(res$forced)

  bundle_dir <- file.path(root, res$path)
  expect_true(dir.exists(bundle_dir))
  # every non-report artifact required by PRD 6.4
  for (f in c("BUNDLE.yml", "MANIFEST.sha256", "environment.json",
              "session-info.txt", "traceability.csv",
              "snapshot/avior.yml", "snapshot/inventory.yml",
              "snapshot/scores.yml", "snapshot/test-results.yml",
              "snapshot/decisions/lme4.yml")) {
    expect_true(file.exists(file.path(bundle_dir, f)), label = f)
  }

  # snapshots are byte-identical copies of the compilation inputs
  for (f in c("avior.yml", "inventory.yml", "scores.yml",
              "test-results.yml")) {
    a <- file.path(root, "validation", f)
    b <- file.path(bundle_dir, "snapshot", f)
    expect_identical(readBin(a, "raw", file.size(a)),
                     readBin(b, "raw", file.size(b)), label = f)
  }

  # the bundle passes independent verification; anchors agree
  v <- avior_verify(bundle_dir)
  expect_identical(v$status, "pass")
  expect_identical(
    v$anchor, avior:::sha256_file(file.path(bundle_dir, "MANIFEST.sha256")))

  # BUNDLE.yml facts reconcile with the snapshots
  b <- avior:::read_yaml_file(file.path(bundle_dir, "BUNDLE.yml"))
  expect_identical(b$avior, 1L)
  expect_identical(b$bundle_id, res$bundle_id)
  expect_identical(b$integrity_check, "passed")
  expect_null(b$forced)
  inv <- avior:::read_yaml_file(file.path(bundle_dir, "snapshot",
                                          "inventory.yml"))
  expect_identical(b$project$lockfile_sha256, inv$lockfile$sha256)
  expect_identical(
    b$project$policy_sha256,
    avior:::sha256_file(file.path(bundle_dir, "snapshot", "avior.yml")))
  expect_identical(b$counts$packages_total, 5L)
  expect_identical(b$counts$decisions_signed, 4L)
  expect_identical(b$counts$tests_run, 2L)
})

test_that("identical inputs rebuild byte-identical bundles (FR-BUNDLE-8)", {
  local_bundle_env()
  root <- local_checked_project()

  res1 <- avior_bundle(root)
  dir1 <- file.path(root, res1$path)
  files <- sort(list.files(dir1, recursive = TRUE, all.files = TRUE,
                           no.. = TRUE))
  hashes1 <- vapply(files, function(f) {
    avior:::sha256_file(file.path(dir1, f))
  }, character(1))

  unlink(dir1, recursive = TRUE)
  res2 <- avior_bundle(root)
  expect_identical(res2$bundle_id, res1$bundle_id)  # epoch-pinned timestamp
  dir2 <- file.path(root, res2$path)
  hashes2 <- vapply(files, function(f) {
    avior:::sha256_file(file.path(dir2, f))
  }, character(1))
  expect_identical(hashes1, hashes2)
})

test_that("existing bundles are never overwritten, even on collision", {
  local_bundle_env()   # fixed epoch -> same timestamp -> forced collision
  root <- local_checked_project()

  res <- avior_bundle(root)
  bundle_dir <- file.path(root, res$path)
  marker <- file.path(bundle_dir, "BUNDLE.yml")
  before <- readBin(marker, "raw", file.size(marker))

  err <- tryCatch(avior_bundle(root), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "never overwritten")
  expect_identical(readBin(marker, "raw", file.size(marker)), before)
  # no staging residue either
  expect_length(list.files(dirname(bundle_dir), pattern = "staging",
                           all.files = TRUE), 0L)
})

test_that("a failing check blocks compilation; --force discloses (FR-BUNDLE-6)", {
  local_bundle_env()
  root <- local_checked_project()
  # break the gate: silently bump a decision's version -> stale_decision
  f <- file.path(root, "validation", "decisions", "survival.yml")
  writeLines(sub('version: "3.5-7"', 'version: "3.4-0"', readLines(f)), f)
  stopifnot(identical(avior_check(root)$status, "fail"))

  res <- avior_bundle(root)
  expect_identical(res$status, "fail")
  expect_true(length(res$findings) > 0)
  expect_length(list.files(file.path(root, "validation", "evidence")), 0L)

  forced <- avior_bundle(root, force = TRUE)
  expect_identical(forced$status, "ok")
  expect_identical(forced$integrity_check, "failed")
  expect_true(forced$forced)
  b <- avior:::read_yaml_file(
    file.path(root, forced$path, "BUNDLE.yml"))
  expect_identical(b$integrity_check, "failed")
  expect_true(b$forced)
  expect_true(b$check_findings >= 1L)
  expect_true("stale_decision" %in% unlist(b$check_finding_types))
  # forced bundles still verify: disclosure, not corruption
  expect_identical(avior_verify(file.path(root, forced$path))$status, "pass")
})

test_that("decisions_signed counts signatures, not decision files", {
  local_bundle_env()
  root <- local_checked_project()
  # blank one signature -> `unsigned` finding -> gate fails -> --force
  f <- file.path(root, "validation", "decisions", "mvtnorm.yml")
  writeLines(sub('^reviewed_by: .*$', 'reviewed_by: ""', readLines(f)), f)
  stopifnot(identical(avior_check(root)$status, "fail"))

  res <- avior_bundle(root, force = TRUE)
  b <- avior:::read_yaml_file(file.path(root, res$path, "BUNDLE.yml"))
  # the same BUNDLE.yml that discloses `unsigned` must not claim all four
  # decisions are signed
  expect_true("unsigned" %in% unlist(b$check_finding_types))
  expect_identical(b$counts$decisions_signed, 3L)
})

test_that("--force tolerates inputs check already reported as findings", {
  local_bundle_env()
  root <- local_checked_project()
  dec <- function(f) file.path(root, "validation", "decisions", f)
  # every flavour of gate failure --force must survive without crashing
  # (FR-BUNDLE-6): invalid YAML in test-results.yml; an UNPARSEABLE
  # decision; a parseable decision that is NOT a decision record; and a
  # schema-valid decision merely missing its signature field
  writeLines("results: [", file.path(root, "validation", "test-results.yml"))
  writeLines("{{{", dec("mvtnorm.yml"))
  writeLines("foo: bar", dec("jsonlite.yml"))
  writeLines(grep("^reviewed_by:", readLines(dec("survival.yml")),
                  value = TRUE, invert = TRUE), dec("survival.yml"))
  gate <- avior_check(root)
  stopifnot(identical(gate$status, "fail"))

  blocked <- avior_bundle(root)
  expect_identical(blocked$status, "fail")     # unforced still blocks

  res <- avior_bundle(root, force = TRUE)
  expect_identical(res$status, "ok")
  expect_true(res$forced)
  b <- avior:::read_yaml_file(file.path(root, res$path, "BUNDLE.yml"))
  expect_identical(b$integrity_check, "failed")
  expect_identical(b$counts$tests_run, 0L)     # unusable evidence != evidence
  # mvtnorm (unparseable) and jsonlite (not a decision record) are
  # unavailable; survival lost its signature; only lme4 counts as signed
  expect_identical(b$counts$decisions_signed, 1L)
  # the broken inputs are still snapshot verbatim for the audit trail
  snap <- file.path(root, res$path, "snapshot")
  expect_identical(readLines(file.path(snap, "test-results.yml")),
                   "results: [")
  expect_identical(readLines(file.path(snap, "decisions", "jsonlite.yml")),
                   "foo: bar")
  # unavailable decisions leave blank trace cells rather than crashing
  csv <- readLines(file.path(root, res$path, "traceability.csv"),
                   encoding = "UTF-8")
  expect_match(csv[startsWith(csv, "jsonlite,")], "^jsonlite,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,,")
  # and the bundle still verifies: disclosure, not corruption
  expect_identical(avior_verify(file.path(root, res$path))$status, "pass")
})

test_that("traceability.csv follows the PRD 6.5 schema", {
  local_bundle_env()
  root <- local_checked_project()
  res <- avior_bundle(root)
  csv <- readLines(file.path(root, res$path, "traceability.csv"),
                   encoding = "UTF-8")
  expect_identical(csv[1], paste(
    "package,version,classification,role,score,tier,decision",
    "use_statement_ref,decision_file,reviewed_by,decision_date",
    "test_files,test_status,notes", sep = ","))
  # rows in C-locale package order
  pkgs <- vapply(strsplit(csv[-1], ",", fixed = TRUE),
                 function(x) x[1], character(1))
  expect_identical(pkgs, avior:::sort_c(pkgs))
  # transitive row: version_managed with blank score/tier/refs (PRD 6.5)
  minqa <- csv[startsWith(csv, "minqa,")]
  expect_match(minqa, "^minqa,1\\.2\\.6,contributed,transitive,,,version_managed,,,,,,,")
  # in-scope row links package -> decision -> tests -> result
  lme4 <- csv[startsWith(csv, "lme4,")]
  expect_match(lme4, "include_with_tests")
  expect_match(lme4, "decisions/lme4\\.yml#use_statement")
  expect_match(lme4, "tests/test-lme4-fit\\.R")
  expect_match(lme4, ",pass,")
})

test_that("out-of-scope direct rows are exempt or excluded (PRD 6.5)", {
  # unit level: the fixture has no such rows (its recommended package is
  # force-included), so exercise trace_row directly
  exempt <- avior:::trace_row(
    list(name = "MASS", version = "7.3-60", classification = "recommended",
         role = "direct", in_scope = FALSE),
    decisions = list(), scores = NULL, tests = NULL)
  expect_identical(exempt$decision, "exempt")
  expect_true(is.na(exempt$score) && is.na(exempt$tier))
  expect_true(is.na(exempt$decision_file))

  excluded <- avior:::trace_row(
    list(name = "dplyr", version = "1.1.4", classification = "contributed",
         role = "direct", in_scope = FALSE, overridden = TRUE,
         override_source = "avior.yml scope.exclude"),
    decisions = list(), scores = NULL, tests = NULL)
  expect_identical(excluded$decision, "excluded")
})

test_that("environment.json records the FR-BUNDLE-5 fingerprint", {
  local_bundle_env()
  root <- local_checked_project()
  res <- avior_bundle(root)
  env <- jsonlite::fromJSON(
    file.path(root, res$path, "environment.json"), simplifyVector = FALSE)

  expect_identical(env$r_version, "4.3.2")
  expect_identical(env$platform, "x86_64-pc-linux-gnu")
  expect_identical(env$locale$LC_COLLATE, "C")
  expect_match(env$blas, "BLAS")
  expect_null(env$container)
  expect_identical(env$session_info, "session-info.txt")
  # PPM snapshot date extracted from the repository URL
  expect_identical(env$repositories[[1]]$snapshot, "2024-01-15")
  expect_identical(env$lockfile$sha256,
                   avior:::sha256_file(file.path(root, "renv.lock")))
  expect_identical(env$package_count$total, 5L)
  expect_identical(env$package_count$force_included, 1L)

  # session-info.txt carries the captured sessionInfo text
  si <- readLines(file.path(root, res$path, "session-info.txt"))
  expect_match(si[1], "mocked session info")
})

test_that("unobservable environment facts record \"unknown\", never omit keys", {
  blank <- fixed_session()
  blank$blas <- ""
  blank$lapack <- ""
  testthat::local_mocked_bindings(capture_session = function() blank,
                                  .package = "avior")
  root <- local_checked_project()
  res <- avior_bundle(root)
  env <- jsonlite::fromJSON(
    file.path(root, res$path, "environment.json"), simplifyVector = FALSE)
  expect_identical(env$blas, "unknown")
  expect_identical(env$lapack, "unknown")
})

test_that("--zip writes a deterministic transport artifact that verifies", {
  local_bundle_env()
  root <- local_checked_project()
  res <- avior_bundle(root, zip = TRUE)
  zip_path <- file.path(root, res$zip)
  expect_true(file.exists(zip_path))
  # the zip name matches the evidence/*.zip gitignore glob from `avior init`
  expect_match(basename(res$zip), "^bundle-.*\\.zip$")

  v <- avior_verify(zip_path)
  expect_identical(v$status, "pass")
  expect_identical(v$source, "zip")
  expect_identical(v$anchor, avior_verify(file.path(root, res$path))$anchor)

  # deterministic rebuild: delete both, rebuild, compare zip bytes
  bytes1 <- readBin(zip_path, "raw", file.size(zip_path))
  unlink(file.path(root, res$path), recursive = TRUE)
  unlink(zip_path)
  avior_bundle(root, zip = TRUE)
  bytes2 <- readBin(zip_path, "raw", file.size(zip_path))
  expect_identical(bytes1, bytes2)
})

test_that("CLI: bundle exit codes, JSON envelope, flag validation", {
  local_bundle_env()
  root <- local_checked_project()
  local_with_dir <- function(dir, code) {
    old <- setwd(dir); on.exit(setwd(old), add = TRUE); force(code)
  }
  local_with_dir(root, {
    out <- capture.output(code <- main(c("bundle", "--format", "json")))
    expect_identical(code, 0L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                                 simplifyVector = FALSE)
    expect_identical(parsed$command, "bundle")
    expect_identical(parsed$status, "ok")
    expect_match(parsed$bundle_id, "^bundle-[0-9TZ]+$")
    expect_identical(parsed$integrity_check, "passed")
    expect_true(is.list(parsed$report_files))

    expect_identical(suppressMessages(main(c("bundle", "--bogus"))), 2L)
    # collision with the bundle just built (fixed epoch) -> exit 2
    expect_identical(suppressMessages(main(c("bundle"))), 2L)
  })

  # gate failure -> exit 1 with findings in JSON
  f <- file.path(root, "validation", "decisions", "survival.yml")
  writeLines(sub('version: "3.5-7"', 'version: "3.4-0"', readLines(f)), f)
  local_with_dir(root, {
    expect_identical(suppressMessages(main(c("bundle"))), 1L)
    out <- capture.output(
      code <- suppressMessages(main(c("bundle", "--format", "json"))))
    expect_identical(code, 1L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                                 simplifyVector = FALSE)
    expect_identical(parsed$status, "fail")
    expect_true(length(parsed$findings) > 0)
  })
})
