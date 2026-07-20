# avior test — targeted test execution and test-results evidence
# (FR-TEST-1..3). Discovers testthat files under <validation>/tests/, maps
# each file to its package through the required `# avior-package: <pkg>`
# header, runs them, and writes canonical validation/test-results.yml bound
# to the runtime environment (package version + lockfile SHA-256 + R
# version/platform). Staleness against the inventory baseline is judged by
# `avior check` (the reader); this writer records what actually ran.

testthat_api <- function() {
  if (!requireNamespace("testthat", quietly = TRUE)) {
    avior_abort(paste0(
      "the testthat package is not installed; install it to run `avior test`"
    ))
  }
  list(
    version = as.character(utils::packageVersion("testthat")),
    test_file = function(path) {
      testthat::test_file(path, reporter = "silent")
    }
  )
}

# The version string exactly as the installed DESCRIPTION declares it.
# utils::packageVersion() canonicalizes `-` to `.` (survival "3.8-6" would
# become "3.8.6"), which no longer matches the renv.lock/inventory literal
# and would make freshly generated evidence look stale. Record the raw
# ground truth instead; the check reader compares with package_version
# semantics anyway.
installed_package_version <- function(pkg) {
  as.character(utils::packageDescription(pkg, fields = "Version"))
}

# Wall-clock seam: golden tests mock this so duration_s (the only
# measured, non-reproducible field besides run_at) becomes deterministic.
test_timer <- function(expr) {
  t0 <- proc.time()[["elapsed"]]
  value <- force(expr)
  list(value = value, elapsed = proc.time()[["elapsed"]] - t0)
}

# Test files live directly under <validation>/tests/. testthat support
# files (helper-*/setup-*/teardown-*) are tolerated; any OTHER .R file is
# an execution error — a test-looking file that is silently not run would
# be a fail-open trust defect for an evidence tool.
discover_test_files <- function(cfg) {
  dir <- file.path(cfg$paths$validation, "tests")
  if (!dir.exists(dir)) return(character(0))
  all_r <- sort_c(list.files(dir, pattern = "\\.[Rr]$"))
  is_test <- grepl("^test", all_r)
  is_support <- grepl("^(helper|setup|teardown)", all_r)
  stray <- all_r[!is_test & !is_support]
  if (length(stray) > 0) {
    avior_abort(paste0(
      "avior test: unexpected .R file(s) under validation/tests/: ",
      paste(stray, collapse = ", "),
      " (test files must be named test*.R; support files helper-*/setup-*/",
      "teardown-*.R)"))
  }
  sort_c(all_r[is_test])
}

# FR-TEST-1: every test file declares its package in a header comment.
# Returns the package name, or a character defect message (aggregated by
# the caller into one execution error naming every broken file).
test_file_package <- function(lines, rel) {
  hits <- grep("^#\\s*avior-package\\s*:", lines)
  if (length(hits) == 0) {
    return(structure(paste0(
      rel, ": missing the `# avior-package: <pkg>` header (FR-TEST-1)"),
      class = "avior_mapping_defect"))
  }
  if (length(hits) > 1) {
    return(structure(paste0(
      rel, ": ambiguous mapping -- ", length(hits),
      " `# avior-package:` headers (keep exactly one)"),
      class = "avior_mapping_defect"))
  }
  value <- sub("^#\\s*avior-package\\s*:", "", lines[hits])
  value <- trimws(value)
  if (!grepl("^[A-Za-z][A-Za-z0-9.]*$", value)) {
    return(structure(paste0(
      rel, ": malformed `# avior-package:` header value `", value,
      "` (expected a single valid R package name)"),
      class = "avior_mapping_defect"))
  }
  value
}

# FR-TEST-3: covr coverage as a disclosed reference metric only. Never a
# gate, never fatal: any covr error (uninstalled, no srcrefs on the
# installed package, unsupported layout) silently omits the field.
collect_coverage_ref <- function(pkg, abs_path) {
  if (!requireNamespace("covr", quietly = TRUE)) return(NULL)
  tryCatch({
    cov <- covr::environment_coverage(asNamespace(pkg), abs_path)
    pct <- covr::percent_coverage(cov)
    paste0(avior_format_num(pct), "% (covr ",
           as.character(utils::packageVersion("covr")),
           "; R-level coverage of ", pkg,
           "; reference only, not a gate)")
  }, error = function(e) NULL)
}

# One result row per test file (per-test-file evidence, not only
# per-package). Counts derive from the testthat result data.frame; an
# errored or skipped block can never be reported as a pass.
run_test_file <- function(api, abs_path, rel, pkg, pkg_version, coverage) {
  timed <- test_timer(tryCatch(
    api$test_file(abs_path),
    error = function(e) {
      avior_abort(paste0("avior test: test runner crashed in ", rel, ": ",
                         conditionMessage(e)))
    }
  ))
  df <- as.data.frame(timed$value)
  n <- nrow(df)
  failed <- if (n) sum(df$failed > 0 | df$error) else 0L
  skipped <- if (n) sum(df$skipped & !(df$failed > 0 | df$error)) else 0L
  row <- list(
    file = rel,
    package = pkg,
    package_version = pkg_version,
    tests = as.integer(n),
    passed = as.integer(n - failed - skipped),
    failed = as.integer(failed),
    skipped = as.integer(skipped),
    duration_s = round(as.numeric(timed$elapsed), 4)
  )
  if (isTRUE(coverage)) {
    ref <- collect_coverage_ref(pkg, abs_path)
    if (!is.null(ref)) row$coverage_ref <- ref
  }
  row
}

write_test_results <- function(cfg, rows, environment_binding,
                               testthat_version, run_at) {
  doc <- list(
    avior = 1L,
    generated_by = "avior test",
    testthat_version = testthat_version,
    run_at = run_at,
    environment = environment_binding,
    results = rows
  )
  path <- file.path(cfg$paths$validation, "test-results.yml")
  write_yaml_canonical(doc, path)
  path
}

avior_test <- function(root = ".", coverage = FALSE) {
  cfg <- avior_config_load(root)
  inventory <- read_inventory(cfg)
  api <- testthat_api()

  files <- discover_test_files(cfg)
  tests_dir <- file.path(cfg$paths$validation, "tests")

  # Validate EVERY mapping up front and aggregate the defects: a run that
  # stops at the first broken header makes the user fix files one by one.
  inv_names <- vapply(inventory$packages, function(p) p$name, character(1))
  in_scope <- vapply(inventory$packages, function(p) isTRUE(p$in_scope),
                     logical(1))
  defects <- character(0)
  mapping <- character(0)
  for (f in files) {
    rel <- paste0("tests/", f)
    lines <- readLines(file.path(tests_dir, f), encoding = "UTF-8",
                       warn = FALSE)
    pkg <- test_file_package(lines, rel)
    if (inherits(pkg, "avior_mapping_defect")) {
      defects <- c(defects, unclass(pkg))
      next
    }
    if (!pkg %in% inv_names) {
      defects <- c(defects, paste0(
        rel, ": maps to `", pkg, "`, which is not in the inventory ",
        "(run `avior scan`, or fix the header)"))
      next
    }
    if (!in_scope[match(pkg, inv_names)]) {
      defects <- c(defects, paste0(
        rel, ": maps to `", pkg, "`, which is out of scope ",
        "(pull it back in via avior.yml scope.include, or fix the header)"))
      next
    }
    if (!requireNamespace(pkg, quietly = TRUE)) {
      defects <- c(defects, paste0(
        rel, ": package `", pkg, "` is not installed in this library ",
        "(targeted tests must run against the validated environment)"))
      next
    }
    mapping[rel] <- pkg
  }
  if (length(defects) > 0) {
    avior_abort(paste0(
      "avior test: invalid test-to-package mapping:\n",
      paste0("  - ", defects, collapse = "\n")))
  }

  dep_src <- resolve_dep_source(cfg$root, cfg$scope$lockfile)
  environment_binding <- list(
    lockfile_sha256 = sha256_file(dep_src$file),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform
  )

  rows <- list()
  for (rel in names(mapping)) {
    pkg <- mapping[[rel]]
    rows[[length(rows) + 1L]] <- run_test_file(
      api, file.path(cfg$root, cfg$project$validation_dir, rel), rel, pkg,
      installed_package_version(pkg), coverage)
  }

  path <- write_test_results(cfg, rows, environment_binding,
                             api$version, avior_timestamp())

  # A file that produced no passing test is NOT evidence: all-skipped and
  # zero-test files must never read as success (issue #30 AC — skip/error
  # states cannot be silently reported as pass). An empty run (no files)
  # stays "ok": it claims nothing, and `check` still gates
  # include_with_tests packages on recorded passing evidence.
  failed_total <- sum(vapply(rows, function(r) r$failed, integer(1)))
  no_evidence <- any(vapply(rows, function(r) r$passed == 0L, logical(1)))
  list(
    status = if (failed_total > 0 || no_evidence) "fail" else "ok",
    results = rows,
    environment = environment_binding,
    testthat_version = api$version,
    path = file.path(cfg$project$validation_dir, "test-results.yml")
  )
}
