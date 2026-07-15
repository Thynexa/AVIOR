# PR #21 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every actionable optimization in PR #21, correct the verified riskmetric adapter defects, add repeatable quality gates and tracking artifacts, and re-review the PR until no Critical or Important issue remains.

**Architecture:** Preserve the existing M1 command/config/engine boundaries. Harden only the shared serialization and input-reading seams, add a narrow riskmetric API seam for deterministic unit tests, and use independent GitHub Actions workflows for coverage, lint, and the real riskmetric spike.

**Tech Stack:** R >= 4.1, testthat 3e, cli, yaml, jsonlite, digest, riskmetric 0.2.7, covr, lintr, renv, r-lib/actions v2, GitHub Actions.

## Global Constraints

- Keep text/JSON envelopes and exit codes stable: success 0, validation failure 1, execution error 2.
- Preserve UTF-8, LF-only, trailing-newline, locale-independent canonical artifacts on Linux, macOS, and Windows.
- Write behavior tests before production code and observe the expected failure before implementing.
- Do not implement `avior test`, `avior verify`, or `avior bundle` in this plan.
- Do not claim design partner review was sent or approved without an actual recipient and response.
- Do not make third-party coverage upload credentials a merge prerequisite.
- Fix every Critical and Important review finding before completion.

## File Map

- `R/cli.R`: top-level help/version and the authoritative command list.
- `R/assess.R`: disposable score-cache validation and cache-miss fallback.
- `R/check.R`: fail-closed `test-results.yml` parsing and structure validation.
- `R/canonical.R`: same-directory temporary write and atomic rename.
- `R/engine.R`: riskmetric API seam, column aliases, remote checks, and version binding.
- `tests/testthat/test-{cli,assess,check,canonical,engine}.R`: regression tests for each behavior.
- `tools/riskmetric-spike.R`: real adapter smoke and 5/50-package timing runner.
- `.github/workflows/{riskmetric-smoke,coverage,lint}.yml`: integration and quality gates.
- `.lintr`: baseline-compatible correctness linter selection.
- `renv.lock`: root development dependency lock.
- `docs/qa/design-partner-review-request.md`: send-ready QA request and response form.
- `docs/riskmetric-spike-results.md`: measured run metadata and cold/hot timings.
- `README.md`: coverage/lint status badges.

---

### Task 1: CLI help, version, and authoritative command copy

**Files:**
- Modify: `tests/testthat/test-cli.R`
- Modify: `R/cli.R`

**Interfaces:**
- Produces: `avior_command_names() -> character`, `avior_command_hint() -> character`, and `avior_version() -> character(1)`.
- Preserves: `main(argv) -> invisible integer` and existing JSON envelope conventions.

- [ ] **Step 1: Write failing tests for text and JSON metadata commands**

Add tests that call `main(c("--help"))`, `main(c("--version"))`, and their `--format json` variants. Assert exit 0, all five business commands, array-typed JSON commands, and version equality with `DESCRIPTION`:

```r
test_that("--help and --version are successful text and JSON commands", {
  help_text <- capture.output(help_code <- main("--help"))
  expect_identical(help_code, 0L)
  expect_true(all(c("init", "scan", "assess", "review", "check") %in%
                  unlist(strsplit(paste(help_text, collapse = " "), " "))))

  version_text <- capture.output(version_code <- main("--version"))
  expect_identical(version_code, 0L)
  expect_match(paste(version_text, collapse = ""),
               read.dcf("DESCRIPTION")[1, "Version"], fixed = TRUE)

  help_json <- json_of(c("--help", "--format", "json"))
  expect_identical(help_json$status, "ok")
  expect_true(is.list(help_json$commands))
  expect_setequal(unlist(help_json$commands),
                  c("init", "scan", "assess", "review", "check"))
  expect_identical(json_of(c("--version", "--format", "json"))$status, "ok")
})
```

- [ ] **Step 2: Run the focused tests and observe failure**

Run:

```bash
Rscript -e '.libPaths(c("/tmp/avior-r-lib.qEtVCh", .libPaths())); testthat::test_file("tests/testthat/test-cli.R", reporter="summary")'
```

Expected: FAIL because `--help` and `--version` are unknown commands.

- [ ] **Step 3: Implement metadata commands and shared command copy**

Add the following helpers and switch cases, use the hint in both no-command and unknown-command errors, and fix the file header to `exec/avior`:

```r
avior_command_names <- function() c("init", "scan", "assess", "review", "check")

avior_command_hint <- function() paste(avior_command_names(), collapse = "|")

avior_version <- function() as.character(utils::packageVersion("avior"))

# in run_command()
`--help` = list(
  command = "help", status = "ok", usage = "avior <command> [options]",
  commands = json_array(avior_command_names()),
  options = json_array(c("--format text|json", "--help", "--version"))
),
`--version` = list(command = "version", status = "ok", version = avior_version()),
```

Add text branches in `main()` that print usage/commands or `avior <version>`.

- [ ] **Step 4: Run focused and full CLI tests**

Run the focused command above, then:

```bash
Rscript -e '.libPaths(c("/tmp/avior-r-lib.qEtVCh", .libPaths())); testthat::test_local(filter="cli|phase3-regressions|review-regressions", reporter="summary")'
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/cli.R tests/testthat/test-cli.R
git commit -m "feat: add CLI help and version metadata"
```

### Task 2: Treat invalid score cache entries as cache misses

**Files:**
- Modify: `tests/testthat/test-assess.R`
- Modify: `R/assess.R`

**Interfaces:**
- Produces: `read_score_cache(path, metric_ids) -> list | NULL`.
- Consumes: `read_yaml_file()` and the existing assessment/cache-key flow.

- [ ] **Step 1: Write failing syntax- and structure-corruption tests**

Create a fixture, populate caches, overwrite one cache first with invalid YAML and then with a scalar, and assert only that package is rescored and the cache becomes a valid list:

```r
test_that("invalid score cache entries are recomputed", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng)
  cache <- list.files(file.path(root, "validation", ".cache", "scores"),
                      full.names = TRUE)[1]

  for (bad in list("metrics: [", "scalar")) {
    writeLines(bad, cache)
    before <- counter$n
    expect_no_error(avior_assess(root, engine = eng))
    expect_identical(counter$n, before + 1L)
    expect_true(is.list(avior:::read_yaml_file(cache)))
  }
})
```

- [ ] **Step 2: Run the test and observe the parse/`$` failure**

Run `testthat::test_file("tests/testthat/test-assess.R")` with the temporary library.

Expected: FAIL on corrupt YAML or scalar `$metrics` access.

- [ ] **Step 3: Add the minimal cache validator**

```r
read_score_cache <- function(path, metric_ids) {
  entry <- tryCatch(read_yaml_file(path), error = function(e) NULL)
  if (!is.list(entry) || !is.list(entry$metrics) ||
      !setequal(names(entry$metrics), metric_ids) ||
      (!is.null(entry$na_causes) && !is.list(entry$na_causes))) {
    return(NULL)
  }
  entry
}
```

Replace the direct `read_yaml_file(cache_file)` and duplicate metric-set check with this helper.

- [ ] **Step 4: Run assess and full tests**

Expected: corruption tests pass, the engine counter increases by one per damaged cache, and all existing cache tests remain green.

- [ ] **Step 5: Commit**

```bash
git add R/assess.R tests/testthat/test-assess.R
git commit -m "fix: recover from invalid score caches"
```

### Task 3: Convert invalid test results into a structured check finding

**Files:**
- Modify: `tests/testthat/test-check.R`
- Modify: `R/check.R`

**Interfaces:**
- Produces: `valid_test_results(x) -> logical(1)` and `invalid_test_results_finding() -> avior finding`.
- Preserves: missing file behavior and `avior_check(root)` result schema.

- [ ] **Step 1: Add failing parse, scalar, row-shape, and CLI JSON tests**

For each invalid form (`"results: ["`, `"scalar"`, and a result row without `package_version`), assert `status == "fail"`, finding type `invalid_test_results`, and CLI exit 1 with JSON status `fail`.

```r
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
```

- [ ] **Step 2: Run `test-check.R` and observe exit 2/crashes**

Expected: direct checks error and the CLI maps them to unexpected error/exit 2.

- [ ] **Step 3: Implement structure validation and early finding return**

```r
valid_test_results <- function(x) {
  scalar_text <- function(v) {
    is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
  }
  is.list(x) && (is.null(x$results) ||
    (is.list(x$results) && all(vapply(x$results, function(row) {
      is.list(row) && scalar_text(row$package) &&
        scalar_text(row$package_version) && scalar_text(row$file) &&
        (is.null(row$failed) ||
          (is.numeric(row$failed) && length(row$failed) == 1L))
    }, logical(1)))))
}

invalid_test_results_finding <- function() {
  finding("-", "invalid_test_results",
          "test-results.yml is not valid YAML in the expected schema",
          fix = "re-run `avior test` to regenerate test-results.yml")
}
```

Wrap `read_yaml_file(path)` in `tryCatch`; if parsing or validation fails, return a one-element finding list before iterating rows.

- [ ] **Step 4: Run focused check/CLI tests and the full suite**

Expected: all invalid forms produce exit 1 and no unexpected error.

- [ ] **Step 5: Commit**

```bash
git add R/check.R tests/testthat/test-check.R
git commit -m "fix: report invalid test results as findings"
```

### Task 4: Make canonical writes atomic

**Files:**
- Modify: `tests/testthat/test-canonical.R`
- Modify: `R/canonical.R`

**Interfaces:**
- Preserves: `write_lines_lf(lines, path) -> invisible path`.
- Produces: same-directory `.avior-write-*` temporary files that never remain after success/failure.

- [ ] **Step 1: Add failing replacement and cleanup tests**

Assert an existing target is replaced, bytes remain LF-only, and using a directory as the destination raises `avior_error` without leaving `.avior-write-*` files in the parent.

```r
test_that("write_lines_lf atomically replaces and cleans temporary files", {
  parent <- tempfile("atomic-parent-")
  dir.create(parent)
  on.exit(unlink(parent, recursive = TRUE), add = TRUE)
  path <- file.path(parent, "artifact.yml")
  writeLines("old", path)

  avior:::write_lines_lf(c("new", "内容"), path)
  expect_identical(readLines(path, encoding = "UTF-8"), c("new", "内容"))
  expect_length(list.files(parent, pattern = "^[.]avior-write-"), 0L)

  bad_target <- file.path(parent, "directory-target")
  dir.create(bad_target)
  expect_error(avior:::write_lines_lf("x", bad_target), class = "avior_error")
  expect_length(list.files(parent, pattern = "^[.]avior-write-"), 0L)
})
```

- [ ] **Step 2: Run the canonical tests and confirm the cleanup test fails**

Expected: existing implementation writes directly and does not exercise rename failure semantics.

- [ ] **Step 3: Implement same-directory temporary write and rename**

```r
write_lines_lf <- function(lines, path) {
  tmp <- tempfile(".avior-write-", tmpdir = dirname(path))
  con <- file(tmp, open = "wb")
  closed <- FALSE
  on.exit({
    if (!closed) close(con)
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)
  writeLines(to_utf8(lines), con, sep = "\n", useBytes = TRUE)
  close(con)
  closed <- TRUE
  if (!file.rename(tmp, path)) {
    avior_abort(paste0("could not atomically replace artifact: ", path))
  }
  invisible(path)
}
```

- [ ] **Step 4: Run canonical tests and all artifact/fixture tests**

Run filters `canonical|fixture-drift|scan|assess|review|check`.

Expected: canonical bytes and checked-in fixtures remain unchanged.

- [ ] **Step 5: Commit**

```bash
git add R/canonical.R tests/testthat/test-canonical.R
git commit -m "fix: write canonical artifacts atomically"
```

### Task 5: Correct and continuously smoke-test the riskmetric adapter

**Files:**
- Modify: `tests/testthat/test-engine.R`
- Modify: `R/engine.R`
- Create: `tools/riskmetric-spike.R`
- Create: `.github/workflows/riskmetric-smoke.yml`
- Create: `docs/riskmetric-spike-results.md`
- Modify: `.Rbuildignore`

**Interfaces:**
- Produces: `riskmetric_api()`, `riskmetric_score_ref(ref, metric_ids, api)`, and `riskmetric_assess(pkg, version, metric_ids, opts, api = NULL)`.
- `engine_riskmetric()$assess` delegates to `riskmetric_assess()` without changing the engine contract.

- [ ] **Step 1: Add failing seam tests**

Use a fake API list to assert:

- `last_30_bugs_status` reads the fake `bugs_status` score;
- `remote_checks` requests `source = "pkg_cran_remote"`;
- a default ref version mismatch raises `avior_error` containing both versions;
- a remote-ref failure produces only an NA for `remote_checks`;
- output columns remain `metric_id`, `value`, `status` in policy order.

```r
fake_riskmetric_api <- function(version = "1.0.0", remote_error = FALSE) {
  seen <- new.env(); seen$sources <- character()
  assessment_functions <- function(ids) {
    out <- lapply(ids, function(id) {
      f <- function(x) x
      attr(f, "column_name") <- if (id == "last_30_bugs_status") {
        "bugs_status"
      } else id
      f
    })
    names(out) <- paste0("assess_", ids)
    out
  }
  list(
    pkg_ref = function(pkg, source = NULL) {
      seen$sources <- c(seen$sources, source %||% "default")
      if (identical(source, "pkg_cran_remote") && remote_error) stop("offline")
      list(name = pkg, version = version)
    },
    assessment_functions = assessment_functions,
    pkg_assess = function(ref, assessments, ...) {
      cols <- vapply(assessments, attr, character(1), "column_name")
      stats::setNames(as.list(rep(1, length(cols))), cols)
    },
    pkg_score = function(x, error_handler) {
      stats::setNames(as.list(rep(0.75, length(x))), names(x))
    },
    score_error_NA = function(...) NA_real_,
    seen = seen
  )
}

test_that("riskmetric seam maps aliases, remote refs, and versions", {
  api <- fake_riskmetric_api()
  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", c("last_30_bugs_status", "remote_checks"),
    list(network_available = TRUE), api = api)
  expect_identical(res$metric_id,
                   c("last_30_bugs_status", "remote_checks"))
  expect_identical(res$value, c(0.75, 0.75))
  expect_true("pkg_cran_remote" %in% api$seen$sources)
  expect_error(
    avior:::riskmetric_assess("demo", "2.0.0", "has_news", list(), api),
    class = "avior_error"
  )

  offline <- fake_riskmetric_api(remote_error = TRUE)
  remote <- avior:::riskmetric_assess(
    "demo", "1.0.0", "remote_checks", list(), offline)
  expect_true(is.na(remote$value))
})
```

- [ ] **Step 2: Run `test-engine.R` and observe missing helper failures**

Expected: FAIL because the seam and alias/remote routing do not exist.

- [ ] **Step 3: Implement the API seam, alias mapping, and version guard**

Build `riskmetric_api()` from exported riskmetric functions plus an `assessment_functions(ids)` closure over its namespace. `riskmetric_score_ref()` must read each function's `column_name` attribute, falling back to the policy ID. `riskmetric_assess()` must validate the default ref version before scoring and route only `remote_checks` through a remote CRAN ref; remote creation/scoring errors become NA for that network metric.

Use `riskmetric::score_error_NA` so upstream metric conditions remain disclosed NA values instead of zero-quality values.

```r
riskmetric_api <- function() {
  if (!requireNamespace("riskmetric", quietly = TRUE)) {
    avior_abort("the riskmetric package is not installed; install it to run `avior assess` with the riskmetric engine")
  }
  ns <- asNamespace("riskmetric")
  list(
    pkg_ref = getExportedValue("riskmetric", "pkg_ref"),
    pkg_assess = getExportedValue("riskmetric", "pkg_assess"),
    pkg_score = getExportedValue("riskmetric", "pkg_score"),
    score_error_NA = getExportedValue("riskmetric", "score_error_NA"),
    assessment_functions = function(ids) {
      fnames <- paste0("assess_", ids)
      missing <- fnames[!vapply(fnames, exists, logical(1),
                                envir = ns, inherits = FALSE)]
      if (length(missing)) {
        avior_abort(paste0("riskmetric is missing assessment(s): ",
                           paste(missing, collapse = ", ")))
      }
      mget(fnames, envir = ns, inherits = FALSE)
    }
  )
}

riskmetric_score_ref <- function(ref, metric_ids, api) {
  if (!length(metric_ids)) return(stats::setNames(numeric(), character()))
  assessments <- api$assessment_functions(metric_ids)
  columns <- vapply(seq_along(assessments), function(i) {
    attr(assessments[[i]], "column_name") %||% metric_ids[[i]]
  }, character(1))
  scored <- api$pkg_score(
    api$pkg_assess(ref, assessments = assessments),
    error_handler = api$score_error_NA)
  stats::setNames(vapply(columns, function(column) {
    value <- suppressWarnings(as.numeric(scored[[column]]))
    if (length(value) == 1L) value else NA_real_
  }, numeric(1)), metric_ids)
}

riskmetric_assess <- function(pkg, version, metric_ids, opts, api = NULL) {
  api <- api %||% riskmetric_api()
  ref <- api$pkg_ref(pkg)
  actual <- as.character(ref$version)
  if (!identical(actual, as.character(version))) {
    avior_abort(paste0("riskmetric resolved ", pkg, " ", actual,
                       " but inventory requires ", version))
  }
  values <- stats::setNames(rep(NA_real_, length(metric_ids)), metric_ids)
  local_ids <- setdiff(metric_ids, "remote_checks")
  values[local_ids] <- riskmetric_score_ref(ref, local_ids, api)
  if ("remote_checks" %in% metric_ids) {
    values["remote_checks"] <- tryCatch({
      remote <- api$pkg_ref(pkg, source = "pkg_cran_remote")
      if (!identical(as.character(remote$version), as.character(version))) {
        NA_real_
      } else riskmetric_score_ref(remote, "remote_checks", api)[[1]]
    }, error = function(e) NA_real_)
  }
  data.frame(metric_id = metric_ids, value = unname(values),
             status = ifelse(is.na(values), "na", "ok"),
             stringsAsFactors = FALSE)
}
```

- [ ] **Step 4: Run focused and full unit tests**

Expected: fake API tests and the existing unavailable-riskmetric guard test pass without installing riskmetric locally.

- [ ] **Step 5: Add the real spike runner and workflow**

`tools/riskmetric-spike.R` must create a temporary AVIOR project from installed package metadata, write a minimal inventory for `AVIOR_SPIKE_PACKAGES` packages, run `avior_assess()` twice, print JSON containing R/riskmetric/avior versions, package count, cold seconds, hot seconds, and NA metrics, and fail if cold > 1800 seconds or hot > 300 seconds.

Core runner:

```r
n <- as.integer(Sys.getenv("AVIOR_SPIKE_PACKAGES", "5"))
installed <- as.data.frame(installed.packages(), stringsAsFactors = FALSE)
installed <- installed[is.na(installed$Priority) & installed$Package != "avior", ]
installed <- installed[order(installed$Package), ][seq_len(min(n, nrow(installed))), ]
root <- tempfile("avior-riskmetric-spike-")
dir.create(file.path(root, "validation"), recursive = TRUE)
file.copy(system.file("templates", "avior.yml", package = "avior"),
          file.path(root, "validation", "avior.yml"))
inventory <- list(
  avior = 1L,
  lockfile = list(path = "renv.lock", sha256 = "integration-spike"),
  packages = lapply(seq_len(nrow(installed)), function(i) {
    list(name = installed$Package[[i]], version = installed$Version[[i]],
         in_scope = TRUE)
  })
)
avior:::write_yaml_canonical(
  inventory, file.path(root, "validation", "inventory.yml"))
cold <- system.time(first <- avior_assess(root))["elapsed"]
hot <- system.time(second <- avior_assess(root))["elapsed"]
summary <- list(
  r = R.version.string,
  avior = as.character(utils::packageVersion("avior")),
  riskmetric = as.character(utils::packageVersion("riskmetric")),
  packages = nrow(installed), cold_seconds = unname(cold),
  hot_seconds = unname(hot), na_metrics = unclass(second$na_metrics)
)
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")
stopifnot(cold <= 1800, hot <= 300)
```

Workflow core:

```yaml
name: Riskmetric smoke
on:
  pull_request:
  workflow_dispatch:
    inputs:
      packages:
        description: Number of installed contributed packages to assess
        required: true
        default: '50'
jobs:
  riskmetric-smoke:
    runs-on: ubuntu-latest
    timeout-minutes: 40
    env:
      AVIOR_SPIKE_PACKAGES: ${{ inputs.packages || '5' }}
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: local::., any::riskmetric
          needs: check
      - run: Rscript tools/riskmetric-spike.R
```

The workflow runs 5 packages on pull requests and accepts `workflow_dispatch` input `packages` for the required 50-package run. Use Ubuntu, R release, `setup-r-dependencies@v2`, and a 40-minute timeout.

- [ ] **Step 6: Record actual 50-package evidence after the workflow run**

Write the workflow URL, commit SHA, package count, versions, cold/hot timings, and NA disclosure into `docs/riskmetric-spike-results.md`. Do not insert estimated values.

- [ ] **Step 7: Commit**

```bash
git add R/engine.R tests/testthat/test-engine.R tools/riskmetric-spike.R \
  .github/workflows/riskmetric-smoke.yml docs/riskmetric-spike-results.md \
  .Rbuildignore
git commit -m "fix: harden the riskmetric adapter contract"
```

### Task 6: Add baseline-compatible coverage and lint gates

**Files:**
- Create: `.github/workflows/coverage.yml`
- Create: `.github/workflows/lint.yml`
- Create: `.lintr`
- Modify: `.Rbuildignore`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`

**Interfaces:**
- Produces: `test-coverage` and `lint` GitHub check names plus workflow badges.

- [ ] **Step 1: Add a correctness-focused lintr configuration**

Use the official correctness tag but remove `object_usage_linter` and `namespace_linter`, whose package-install/cross-file behavior produces false positives in this hand-written-NAMESPACE repository:

```dcf
linters: linters_with_defaults(
    defaults = linters_with_tags("correctness"),
    object_usage_linter = NULL,
    namespace_linter = NULL
  )
```

- [ ] **Step 2: Run lintr locally**

Run:

```bash
Rscript -e '.libPaths(c("/tmp/avior-r-lib.qEtVCh", .libPaths())); x <- lintr::lint_package(); print(x); quit(status=as.integer(length(x) > 0))'
```

Expected: zero lints. Fix genuine selected-linter findings rather than excluding files.

- [ ] **Step 3: Add official-template-derived workflows**

Coverage installs `any::covr, any::xml2`, runs `covr::package_coverage(quiet=FALSE, clean=FALSE)`, writes `cobertura.xml`, and uploads it with `actions/upload-artifact@v7`. Lint installs `any::lintr, local::.` and runs `lintr::lint_package()` with `LINTR_ERROR_ON_LINT=true`.

Use `actions/checkout@v6` in all three workflows and update the existing CI checkout action to the same major.

Coverage job body:

```yaml
permissions: read-all
jobs:
  test-coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::covr, any::xml2
          needs: coverage
      - name: Test coverage
        shell: Rscript {0}
        run: |
          cov <- covr::package_coverage(quiet = FALSE, clean = FALSE)
          print(cov)
          covr::to_cobertura(cov)
      - uses: actions/upload-artifact@v7
        with:
          name: cobertura
          path: cobertura.xml
```

Lint job body:

```yaml
permissions: read-all
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::lintr, local::.
          needs: lint
      - name: Lint
        run: lintr::lint_package()
        shell: Rscript {0}
        env:
          LINTR_ERROR_ON_LINT: true
```

- [ ] **Step 4: Add workflow status badges and validate YAML**

Add `coverage.yml/badge.svg` and `lint.yml/badge.svg` badges next to CI. Parse every workflow using `yaml::read_yaml()`.

- [ ] **Step 5: Run local coverage**

Run `covr::package_coverage(quiet=FALSE, clean=FALSE)` and print `covr::percent_coverage()`. Require successful execution but do not invent a percentage threshold.

- [ ] **Step 6: Commit**

```bash
git add .lintr .Rbuildignore .github/workflows/ci.yml \
  .github/workflows/coverage.yml .github/workflows/lint.yml README.md
git commit -m "ci: add coverage and correctness lint gates"
```

### Task 7: Add renv dogfooding and design-partner QA materials

**Files:**
- Create: `renv.lock`
- Create: `docs/qa/design-partner-review-request.md`
- Modify: `.Rbuildignore`
- Modify: `docs/README.md`

**Interfaces:**
- Produces: a root dependency lock and a send-ready QA artifact; does not activate renv automatically.

- [ ] **Step 1: Generate a lockfile without `.Rprofile` activation**

Use renv's lockfile/dependency APIs to capture DESCRIPTION Depends/Imports/Suggests plus testthat, covr, lintr, and renv. Verify `renv::lockfile_read("renv.lock")` succeeds and contains `riskmetric`, `testthat`, `covr`, and `lintr`.

```r
packages <- c("cli", "digest", "jsonlite", "yaml", "testthat",
              "covr", "lintr", "renv")
lock <- renv::lockfile_create(
  type = "all", packages = packages,
  libpaths = c("/tmp/avior-r-lib.qEtVCh", .libPaths()), project = ".")
renv::lockfile_write(lock, file = "renv.lock", project = ".")
renv::record("riskmetric@0.2.7", lockfile = "renv.lock", project = ".")
parsed <- renv::lockfile_read("renv.lock")
stopifnot(all(c("riskmetric", "testthat", "covr", "lintr") %in%
              names(parsed$Packages)))
```

- [ ] **Step 2: Add build exclusions and validate lock status**

Add anchored `renv.lock` and `.lintr` patterns to `.Rbuildignore`. Run `renv::dependencies()` and compare its package set to lockfile records; document deliberate tooling-only records.

- [ ] **Step 3: Write the QA request and feedback form**

The document must link the example bundle and ask for decisions on signature flow, report hierarchy, traceability, environment fingerprint, manifest verification, and forced-gate disclosure. Include fields for reviewer, organization, date, decision (`accepted`, `accepted_with_changes`, `rejected`), blocking changes, and optional changes. State `Delivery status: ready to send; recipient/channel not supplied`.

Use this exact structure:

```markdown
# Design Partner Evidence-Bundle QA Request

**Artifact:** `../../examples/minimal-project/validation/evidence/bundle-20260708T120000Z/`

**Delivery status:** Ready to send; recipient/channel not supplied.

## Review decisions requested

- Can this artifact set enter your existing review and signature workflow?
- Does `report.html` expose scope, limitations, and forced-gate status prominently enough?
- Can `traceability.csv` support requirement-to-evidence review without manual reconstruction?
- Is `environment.json` sufficient to identify the execution environment?
- Can an independent reviewer use `MANIFEST.sha256` to detect modification?

## Response

- Reviewer:
- Organization:
- Review date:
- Decision: accepted | accepted_with_changes | rejected
- Blocking changes:
- Optional changes:
- Notes on signature workflow:
```

- [ ] **Step 4: Validate documentation links and lock JSON**

Use `rg` to confirm every linked relative path exists and `jsonlite::validate(readChar("renv.lock", file.size("renv.lock")))` returns true.

- [ ] **Step 5: Commit**

```bash
git add renv.lock .Rbuildignore docs/qa/design-partner-review-request.md docs/README.md
git commit -m "docs: prepare dependency and partner QA evidence"
```

### Task 8: Create the five M2 deferred-work issues

**Files:**
- External: `Thynexa/AVIOR` GitHub issues.

**Interfaces:**
- Produces: five open issue URLs referenced from PR #21.

- [ ] **Step 1: Search for duplicates immediately before creation**

Use `gh issue list --state all --search` for each FR/keyword. Reuse an existing matching issue instead of creating a duplicate.

- [ ] **Step 2: Create one issue per roadmap item**

Each body must contain Context, Acceptance criteria, Non-goals, and Source sections. Titles:

1. `feat(scan): fall back to DESCRIPTION when renv.lock is absent`
2. `feat(assess): expose refresh_na as a CLI option`
3. `feat(check): report unknown scope references as findings`
4. `feat(init): generate GitHub or GitLab CI workflows`
5. `design(scan): define ownership of inventory notes across rescans`

Use these exact context and acceptance sections; append the same Non-goals and Source sections shown below to every issue:

```markdown
### DESCRIPTION fallback
## Context
`avior scan` currently requires `renv.lock`; FR-SCAN-1 also requires a DESCRIPTION fallback for package projects without renv.
## Acceptance criteria
- When `renv.lock` is absent and DESCRIPTION is valid, scan inventories Depends, Imports, and LinkingTo dependencies.
- Output records which source produced the inventory and remains deterministic.
- Missing or malformed inputs preserve fail-closed CLI exit semantics.

### refresh_na CLI
## Context
`avior_assess(refresh_na=)` exists in the R API but the CLI cannot disable automatic refresh of network-cause NA cache entries.
## Acceptance criteria
- A documented CLI option maps explicitly to `refresh_na = TRUE/FALSE`.
- Text and JSON invocations reject duplicates and invalid values.
- Cache-call-count tests prove both modes.

### Unknown scope references
## Context
Unknown scope include/exclude package names currently warn during scan but are not represented in the final check result.
## Acceptance criteria
- `avior check` emits a typed finding for every unknown include/exclude reference.
- Findings identify the package, source field, and corrective action.
- Text/JSON output and exit 1 behavior have regression tests.

### CI generation
## Context
FR-INIT-3 requires `avior init --ci github|gitlab`; init currently creates validation files only.
## Acceptance criteria
- GitHub and GitLab selections generate deterministic, non-destructive workflow files.
- Existing workflow files are never overwritten.
- Unsupported/duplicate options return execution error exit 2.

### Inventory note ownership
## Context
Rescan owns `inventory.yml` as a generated artifact and overwrites hand-edited `note:` fields; the product needs an explicit ownership and migration policy.
## Acceptance criteria
- The chosen source of human notes is documented with rationale.
- Rescan behavior is deterministic and cannot silently discard supported user input.
- Tests cover the selected preservation or decisions-file migration behavior.

## Non-goals
- No unrelated M2 command implementation.

## Source
- `docs/superpowers/plans/2026-07-12-m2-roadmap.md` §2
- PR #21 project optimization review
```

- [ ] **Step 3: Verify all five are open and unique**

Query by returned issue numbers and store the URLs for the final PR summary.

### Task 9: Full verification, push, adversarial review, and closure loop

**Files:**
- Modify only files required by verified review findings.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: updated PR #21 with green checks and no unresolved Critical/Important review finding.

- [ ] **Step 1: Run fresh local verification**

Run full testthat, `R CMD build`, `R CMD check --no-manual --as-cran`, lintr, covr, workflow YAML parsing, renv lock validation, `git diff --check`, and CLI help/version smoke. Record exact counts and exit codes.

- [ ] **Step 2: Review the complete diff against the design and PR #21 checklist**

Check every numbered suggestion, error/exit invariant, cross-platform writer behavior, test coverage, workflow permissions, and external-status claim. Fix any discovered issue test-first.

- [ ] **Step 3: Push to the existing PR branch**

Push local HEAD to `origin/claude/project-optimization-review-0bh44n` without force.

- [ ] **Step 4: Wait for all PR checks and run the 50-package workflow dispatch**

Require the four matrix R CMD checks, coverage, lint, and 5-package riskmetric smoke to pass. Dispatch 50 packages, wait for completion, record real results, commit/push the evidence update, and re-run affected checks.

- [ ] **Step 5: Perform independent adversarial code review**

Review from the PR base SHA to final head. Fix Critical and Important findings, rerun the narrow regression first, then the complete verification suite, and push again. Repeat until a fresh review finds none.

- [ ] **Step 6: Completion audit**

Re-read the design completion criteria line by line and attach one authoritative evidence source to each. Confirm clean worktree, remote head equality, five issue URLs, QA delivery status accuracy, and all GitHub checks green before marking the goal complete.
