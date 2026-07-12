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
