# avior_assess (FR-ASSESS-1..5, FR-X-5): aggregation, tiers, na_action,
# NA-cause-aware cache, run-mode disclosure.

# goodness values calibrated to land the example's tiers:
# risk = 1 - weighted.mean(value, w)
mock_values <- function() {
  metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
               "downloads_1yr", "covr_coverage", "last_30_bugs_status")
  as_vals <- function(v) stats::setNames(as.list(rep(v, length(metrics))), metrics)
  list(
    jsonlite = as_vals(0.9),   # risk 0.1  -> low
    lme4     = as_vals(0.4),   # risk 0.6  -> high
    mvtnorm  = as_vals(0.6),   # risk 0.4  -> medium
    survival = as_vals(0.35)   # risk 0.65 -> high
  )
}

assess_fixture <- function(engine, ...) {
  root <- local_example_project()
  unlink(file.path(root, "validation", "scores.yml"))
  avior_scan(root)
  avior_assess(root, engine = engine, ...)
  list(root = root,
       scores = avior:::read_yaml_file(file.path(root, "validation", "scores.yml")))
}

test_that("deep assess reproduces the example tiers and schema", {
  eng <- avior:::mock_engine(mock_values(),
                             execution_metrics = "covr_coverage",
                             network_metrics = c("downloads_1yr",
                                                 "last_30_bugs_status"))
  out <- assess_fixture(eng, deep = TRUE)
  s <- out$scores
  expect_identical(s$avior, 1L)
  expect_identical(s$generated_by, "avior assess")
  expect_identical(s$engine$id, "mock")
  expect_identical(s$run$deep, TRUE)
  expect_identical(names(s$packages), c("jsonlite", "lme4", "mvtnorm", "survival"))
  expect_identical(s$packages$jsonlite$tier, "low")
  expect_identical(s$packages$mvtnorm$tier, "medium")
  expect_identical(s$packages$lme4$tier, "high")
  expect_identical(s$packages$survival$tier, "high")
  expect_equal(s$packages$jsonlite$score, 0.1, tolerance = 1e-9)
  expect_identical(s$na_metrics, list())
  expect_identical(s$packages$jsonlite$version, "1.8.8")
})

test_that("without --deep, execution metrics become NA (execution cause)", {
  eng <- avior:::mock_engine(mock_values(), execution_metrics = "covr_coverage")
  out <- assess_fixture(eng, deep = FALSE)
  s <- out$scores
  # covr_coverage (weight 2 of 5.5) reweighted away: jsonlite all-0.9 stays 0.1
  expect_true("covr_coverage" %in% unlist(s$packages$jsonlite$na_metrics))
  expect_true("covr_coverage" %in% unlist(s$na_metrics))
  expect_equal(s$packages$jsonlite$score, 0.1, tolerance = 1e-9)
})

test_that("na_action: zero penalises, fail raises avior_na_error (exit 1 path)", {
  vals <- mock_values()
  vals$jsonlite$downloads_1yr <- NULL   # missing network metric
  eng <- avior:::mock_engine(vals, network_metrics = "downloads_1yr",
                             execution_metrics = "covr_coverage")

  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("na_action: reweight", "na_action: zero", readLines(f)), f)
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE, network_available = FALSE)
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  # zero: goodness 0 for downloads (w=1): risk = 1 - (0.9*4.5)/5.5;
  # tolerance covers the canonical 4-decimal serialization (FR-X-8)
  expect_equal(s$packages$jsonlite$score, 1 - 0.9 * 4.5 / 5.5, tolerance = 1e-3)

  writeLines(sub("na_action: zero", "na_action: fail", readLines(f)), f)
  expect_error(avior_assess(root, engine = eng, deep = TRUE,
                            network_available = FALSE),
               class = "avior_na_error")
})

test_that("cache: second run makes zero engine calls and is byte-identical", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), execution_metrics = "covr_coverage",
                             counter = counter)
  root <- local_example_project()
  unlink(file.path(root, "validation", "scores.yml"))
  avior_scan(root)

  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752307200")
  on.exit(if (is.na(old)) Sys.unsetenv("SOURCE_DATE_EPOCH") else
            Sys.setenv(SOURCE_DATE_EPOCH = old), add = TRUE)

  avior_assess(root, engine = eng, deep = TRUE)
  calls_first <- counter$n
  expect_identical(calls_first, 4L)
  p <- file.path(root, "validation", "scores.yml")
  first <- readBin(p, "raw", file.size(p))

  avior_assess(root, engine = eng, deep = TRUE)
  expect_identical(counter$n, calls_first)          # all served from cache
  expect_identical(readBin(p, "raw", file.size(p)), first)
})

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

test_that("semantically invalid score cache entries only recompute their package", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)

  cache_files <- list.files(
    file.path(root, "validation", ".cache", "scores"),
    full.names = TRUE
  )
  cache_entries <- lapply(cache_files, avior:::read_yaml_file)
  cache <- cache_files[vapply(cache_entries, function(entry) {
    identical(entry$package, "jsonlite")
  }, logical(1))]
  expect_length(cache, 1L)
  pristine <- avior:::read_yaml_file(cache)

  corruptions <- list(
    character_metric = function(entry) {
      entry$metrics$has_news <- "invalid"
      entry
    },
    nested_metric = function(entry) {
      entry$metrics$has_news <- list(NA_real_)
      entry
    },
    out_of_range_metric = function(entry) {
      entry$metrics$has_news <- 1.1
      entry
    },
    cause_for_non_na_metric = function(entry) {
      entry$na_causes <- list(has_news = "execution")
      entry
    },
    unsupported_na_cause = function(entry) {
      entry$metrics$has_news <- NA_real_
      entry$na_metrics <- "has_news"
      entry$na_causes <- list(has_news = "other")
      entry
    },
    unnamed_na_cause = function(entry) {
      entry$metrics$has_news <- NA_real_
      entry$na_metrics <- "has_news"
      entry$na_causes <- list("execution")
      entry
    },
    missing_na_metric = function(entry) {
      entry$metrics$has_news <- NA_real_
      entry$na_causes <- list(has_news = "execution")
      entry
    },
    false_na_metric = function(entry) {
      entry$na_metrics <- "has_news"
      entry
    },
    duplicate_na_metric = function(entry) {
      entry$metrics$has_news <- NA_real_
      entry$na_metrics <- c("has_news", "has_news")
      entry$na_causes <- list(has_news = "execution")
      entry
    },
    empty_scored_at = function(entry) {
      entry$scored_at <- ""
      entry
    },
    non_timestamp_scored_at = function(entry) {
      entry$scored_at <- "not-a-timestamp"
      entry
    },
    missing_utc_marker_scored_at = function(entry) {
      entry$scored_at <- "2026-07-16T09:11:11"
      entry
    },
    invalid_calendar_date_scored_at = function(entry) {
      entry$scored_at <- "2026-02-31T00:00:00Z"
      entry
    }
  )

  for (corrupt in corruptions) {
    avior:::write_yaml_canonical(corrupt(pristine), cache)
    before <- counter$n
    expect_no_error(avior_assess(root, engine = eng, deep = TRUE))
    expect_identical(counter$n, before + 1L)
  }
})

test_that("canonical UTC cache timestamps remain cache hits", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)

  cache_files <- list.files(
    file.path(root, "validation", ".cache", "scores"),
    full.names = TRUE
  )
  cache_entries <- lapply(cache_files, avior:::read_yaml_file)
  cache <- cache_files[vapply(cache_entries, function(entry) {
    identical(entry$package, "jsonlite")
  }, logical(1))]
  entry <- avior:::read_yaml_file(cache)
  entry$scored_at <- "2026-07-16T09:11:11Z"
  avior:::write_yaml_canonical(entry, cache)

  before <- counter$n
  expect_no_error(avior_assess(root, engine = eng, deep = TRUE))
  expect_identical(counter$n, before)
})

test_that("NULL score cache metrics remain valid missing values", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)

  cache_files <- list.files(
    file.path(root, "validation", ".cache", "scores"),
    full.names = TRUE
  )
  cache_entries <- lapply(cache_files, avior:::read_yaml_file)
  cache <- cache_files[vapply(cache_entries, function(entry) {
    identical(entry$package, "jsonlite")
  }, logical(1))]
  entry <- avior:::read_yaml_file(cache)
  entry$metrics["has_news"] <- list(NULL)
  entry$na_metrics <- c(entry$na_metrics, "has_news")
  entry$na_causes <- c(entry$na_causes, list(has_news = "execution"))
  avior:::write_yaml_canonical(entry, cache)

  before <- counter$n
  expect_no_error(avior_assess(root, engine = eng, deep = TRUE))
  expect_identical(counter$n, before)
})

test_that("missing network NA causes invalidate only the damaged package cache", {
  vals <- mock_values()
  vals$jsonlite$downloads_1yr <- NULL
  vals$jsonlite$covr_coverage <- NULL
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(
    vals,
    network_metrics = "downloads_1yr",
    execution_metrics = "covr_coverage",
    counter = counter
  )
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)

  cache_files <- list.files(
    file.path(root, "validation", ".cache", "scores"),
    full.names = TRUE
  )
  cache_entries <- lapply(cache_files, avior:::read_yaml_file)
  cache <- cache_files[vapply(cache_entries, function(entry) {
    identical(entry$package, "jsonlite")
  }, logical(1))]
  expect_length(cache, 1L)
  pristine <- avior:::read_yaml_file(cache)
  expect_setequal(unlist(pristine$na_metrics),
                  c("downloads_1yr", "covr_coverage"))

  missing_causes <- list(
    all = list(),
    network_key = pristine$na_causes["covr_coverage"]
  )
  for (causes in missing_causes) {
    entry <- pristine
    entry$na_causes <- causes
    avior:::write_yaml_canonical(entry, cache)
    before <- counter$n
    expect_no_error(avior_assess(root, engine = eng, deep = TRUE))
    expect_identical(counter$n, before + 1L)
  }
})

test_that("cache: network-cause NA hits are re-scored when network is back (B2)", {
  vals <- mock_values()
  vals$jsonlite$downloads_1yr <- NULL
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(vals, network_metrics = "downloads_1yr",
                             execution_metrics = "covr_coverage",
                             counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)   # jsonlite has a network NA
  n1 <- counter$n

  # network metric now resolvable: the improvable hit must re-score jsonlite
  eng2 <- avior:::mock_engine(mock_values(), network_metrics = "downloads_1yr",
                              execution_metrics = "covr_coverage",
                              counter = counter)
  avior_assess(root, engine = eng2, deep = TRUE)
  expect_identical(counter$n, n1 + 1L)            # only jsonlite re-assessed
  s <- avior:::read_yaml_file(file.path(root, "validation", "scores.yml"))
  expect_null(s$packages$jsonlite$na_metrics)

  # execution-cause NAs must NOT trigger re-scoring (no --deep loop)
  counter$n <- 0L
  root2 <- local_example_project()
  avior_scan(root2)
  avior_assess(root2, engine = eng2, deep = FALSE)  # covr NA, execution cause
  n2 <- counter$n
  avior_assess(root2, engine = eng2, deep = FALSE)
  expect_identical(counter$n, n2)                   # all cache hits
})

test_that("--only restricts fresh scoring to the named package (FR-ASSESS-5)", {
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(mock_values(), execution_metrics = "covr_coverage",
                             counter = counter)
  root <- local_example_project()
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)
  n1 <- counter$n
  avior_assess(root, engine = eng, deep = TRUE, only = "lme4")
  expect_identical(counter$n, n1 + 1L)   # lme4 forced fresh, rest cached
  expect_error(avior_assess(root, engine = eng, deep = TRUE, only = "nope"),
               class = "avior_error")
})

test_that("weights referencing unregistered metrics abort (PRD 7.2)", {
  eng <- avior:::mock_engine(mock_values())
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("has_vignettes: 0.5", "not_a_metric: 0.5", readLines(f)), f)
  avior_scan(root)
  expect_error(avior_assess(root, engine = eng), class = "avior_error")
})

test_that("assess requires a prior scan", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "inventory.yml"))
  expect_error(avior_assess(root, engine = avior:::mock_engine(mock_values())),
               class = "avior_error")
})
