# Engine adapter layer (FR-X-4, PRD 7.2): registry, static metric registry
# availability without the engine package, riskmetric adapter contract.

test_that("avior_engine validates its fields and registers/round-trips", {
  e <- avior:::avior_engine(
    id = "toy", version = "9.9",
    metrics = function() data.frame(id = "m1", description = "d",
                                    needs_network = FALSE, cost = "metadata",
                                    stringsAsFactors = FALSE),
    assess = function(pkg, version, metric_ids, opts) {
      data.frame(metric_id = metric_ids, value = 1, status = "ok",
                 stringsAsFactors = FALSE)
    }
  )
  avior:::engine_register(e)
  expect_identical(avior:::engine_get("toy")$version, "9.9")
  expect_error(avior:::engine_get("nope"), class = "avior_error")
  expect_error(avior:::avior_engine(id = 1, version = "1",
                                    metrics = function() NULL,
                                    assess = function(...) NULL),
               class = "avior_error")
})

test_that("riskmetric adapter: static registry works WITHOUT riskmetric installed", {
  reg <- avior:::engine_metric_registry("riskmetric")
  expect_true(all(c("id", "description", "needs_network", "cost") %in% names(reg)))
  # the ids referenced by PRD 6.2 (example policy + init default template)
  expect_true(all(c("has_vignettes", "has_news", "has_bug_reports_url",
                    "downloads_1yr", "remote_checks", "last_30_bugs_status",
                    "covr_coverage") %in% reg$id))
  expect_identical(reg$cost[reg$id == "covr_coverage"], "execution")
  expect_identical(reg$cost[reg$id == "r_cmd_check"], "execution")
  expect_identical(reg$cost[reg$id == "downloads_1yr"], "network")
  expect_identical(reg$cost[reg$id == "has_vignettes"], "metadata")
})

test_that("riskmetric assess aborts cleanly when riskmetric is unavailable", {
  skip_if(requireNamespace("riskmetric", quietly = TRUE),
          "riskmetric installed; the guard path is not reachable")
  eng <- avior:::engine_get("riskmetric")
  expect_error(eng$assess("jsonlite", "1.8.8", "has_news", list()),
               class = "avior_error")
})

fake_riskmetric_api <- function(version = "1.0.0", remote_error = FALSE,
                                missing_column_name = character(),
                                remote_version = version,
                                remote_score_error = FALSE) {
  seen <- new.env(parent = emptyenv())
  seen$sources <- character()
  assessment_functions <- function(ids) {
    out <- lapply(ids, function(id) {
      f <- function(x) x
      if (!id %in% missing_column_name) {
        attr(f, "column_name") <- if (id == "last_30_bugs_status") {
          "bugs_status"
        } else {
          id
        }
      }
      f
    })
    names(out) <- paste0("assess_", ids)
    out
  }
  list(
    pkg_ref = function(pkg, source = NULL) {
      seen$sources <- c(seen$sources, source %||% "default")
      if (identical(source, "pkg_cran_remote") && remote_error) {
        stop("offline")
      }
      list(
        name = pkg,
        version = if (identical(source, "pkg_cran_remote")) {
          remote_version
        } else {
          version
        },
        source = source %||% "default"
      )
    },
    assessment_functions = assessment_functions,
    pkg_assess = function(ref, assessments, ...) {
      cols <- vapply(seq_along(assessments), function(i) {
        attr(assessments[[i]], "column_name") %||% names(assessments)[[i]]
      }, character(1))
      out <- stats::setNames(as.list(rep(1, length(cols))), cols)
      attr(out, "source") <- ref$source
      out
    },
    pkg_score = function(x, error_handler) {
      if (remote_score_error &&
          identical(attr(x, "source"), "pkg_cran_remote")) {
        stop("remote scoring failed")
      }
      stats::setNames(as.list(rep(0.75, length(x))), names(x))
    },
    score_error_NA = function(...) NA_real_,
    seen = seen
  )
}

test_that("riskmetric seam maps score aliases in policy order", {
  api <- fake_riskmetric_api()
  ids <- c("has_news", "last_30_bugs_status", "has_vignettes")

  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", ids, list(network_available = TRUE), api = api
  )

  expect_identical(names(res), c("metric_id", "value", "status"))
  expect_identical(res$metric_id, ids)
  expect_identical(res$value, rep(0.75, length(ids)))
  expect_identical(res$status, rep("ok", length(ids)))
})

test_that("riskmetric seam falls back to the policy id for unnamed columns", {
  api <- fake_riskmetric_api(missing_column_name = "has_news")

  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", "has_news", list(), api = api
  )

  expect_identical(res$value, 0.75)
  expect_identical(res$status, "ok")
})

test_that("riskmetric seam uses a remote CRAN ref only for remote checks", {
  api <- fake_riskmetric_api()

  avior:::riskmetric_assess(
    "demo", "1.0.0", c("has_news", "remote_checks"),
    list(network_available = TRUE), api = api
  )

  expect_identical(api$seen$sources, c("default", "pkg_cran_remote"))
})

test_that("riskmetric seam treats dash and dot version separators as equal", {
  # renv.lock says 0.1-6, numeric_version renders 0.1.6: the same version
  # must not abort the assessment (real-world hit: base64enc in CI)
  api <- fake_riskmetric_api(version = "0.1.6")

  res <- avior:::riskmetric_assess(
    "demo", "0.1-6", c("has_news", "remote_checks"),
    list(network_available = TRUE), api
  )

  expect_identical(res$status, c("ok", "ok"))
})

test_that("riskmetric seam rejects a default ref version mismatch", {
  api <- fake_riskmetric_api(version = "1.0.0")

  expect_error(
    avior:::riskmetric_assess("demo", "2.0.0", "has_news", list(), api),
    regexp = "1[.]0[.]0.*2[.]0[.]0",
    class = "avior_error"
  )
})

test_that("riskmetric seam accepts punctuation-equivalent default versions", {
  api <- fake_riskmetric_api(version = "0.1.6")

  res <- avior:::riskmetric_assess(
    "base64enc", "0.1-6", "has_news", list(), api
  )

  expect_identical(res$value, 0.75)
  expect_identical(res$status, "ok")
})

test_that("package version comparison fails closed on invalid versions", {
  ns <- asNamespace("avior")
  expect_true(exists("same_package_version", envir = ns, inherits = FALSE))
  if (!exists("same_package_version", envir = ns, inherits = FALSE)) return()

  expect_false(avior:::same_package_version("not-a-version", "1.0.0"))
  expect_false(avior:::same_package_version(NA_character_, "1.0.0"))
})

test_that("riskmetric seam contains remote ref failures to remote checks", {
  api <- fake_riskmetric_api(remote_error = TRUE)

  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", c("has_news", "remote_checks"),
    list(network_available = TRUE), api
  )

  expect_identical(res$value[[1]], 0.75)
  expect_true(is.na(res$value[[2]]))
  expect_identical(res$status, c("ok", "na"))
})

test_that("riskmetric seam contains remote version mismatches", {
  api <- fake_riskmetric_api(remote_version = "2.0.0")

  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", c("has_news", "remote_checks"),
    list(network_available = TRUE), api
  )

  expect_identical(res$value[[1]], 0.75)
  expect_true(is.na(res$value[[2]]))
  expect_identical(res$status, c("ok", "na"))
})

test_that("riskmetric seam accepts punctuation-equivalent remote versions", {
  api <- fake_riskmetric_api(version = "0.1-6", remote_version = "0.1.6")

  res <- avior:::riskmetric_assess(
    "base64enc", "0.1-6", c("has_news", "remote_checks"),
    list(network_available = TRUE), api
  )

  expect_identical(res$value, c(0.75, 0.75))
  expect_identical(res$status, c("ok", "ok"))
})

test_that("riskmetric seam contains remote scoring failures", {
  api <- fake_riskmetric_api(remote_score_error = TRUE)

  res <- avior:::riskmetric_assess(
    "demo", "1.0.0", c("has_news", "remote_checks"),
    list(network_available = TRUE), api
  )

  expect_identical(res$value[[1]], 0.75)
  expect_true(is.na(res$value[[2]]))
  expect_identical(res$status, c("ok", "na"))
})

test_that("mock engine returns the declared frame shape and marks NAs", {
  eng <- avior:::mock_engine(
    values = list(jsonlite = list(has_news = 0.9)),
    network_metrics = "downloads_1yr"
  )
  res <- eng$assess("jsonlite", "1.8.8", c("has_news", "downloads_1yr"), list())
  expect_identical(names(res), c("metric_id", "value", "status"))
  expect_identical(res$value[res$metric_id == "has_news"], 0.9)
  expect_true(is.na(res$value[res$metric_id == "downloads_1yr"]))
  expect_identical(res$status[res$metric_id == "downloads_1yr"], "na")
  reg <- eng$metrics()
  expect_true(reg$needs_network[reg$id == "downloads_1yr"])
})
