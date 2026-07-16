spike_source_file <- function(...) {
  testthat::test_path("..", "..", ...)
}

spike_installed_matrix <- function(package, version, priority = NA_character_) {
  out <- cbind(Package = package, Version = version, Priority = priority)
  rownames(out) <- seq_len(nrow(out))
  out
}

load_spike_helpers <- function() {
  spike <- spike_source_file("tools", "riskmetric-spike.R")
  skip_if_not(file.exists(spike), "spike runner is excluded from built packages")
  env <- new.env(parent = globalenv())
  sys.source(spike, envir = env)
  env
}

spike_assessment <- function(package_names) {
  packages <- rep(list(list()), length(package_names))
  names(packages) <- package_names
  list(packages = packages, na_metrics = character())
}

test_that("riskmetric spike parses a strict positive package count", {
  helpers <- load_spike_helpers()
  expect_true(exists(
    "riskmetric_spike_package_count", envir = helpers, inherits = FALSE
  ))
  if (!exists(
    "riskmetric_spike_package_count", envir = helpers, inherits = FALSE
  )) return()

  expect_identical(helpers$riskmetric_spike_package_count("50"), 50L)
  for (value in c("5.5", "0", "abc", "", "2147483648", NA_character_)) {
    expect_error(
      helpers$riskmetric_spike_package_count(value),
      "positive integer",
      info = paste("value:", dQuote(value))
    )
  }
})

test_that("riskmetric spike selects stable distinct installed packages", {
  helpers <- load_spike_helpers()
  expect_true(exists(
    "riskmetric_spike_select_packages", envir = helpers, inherits = FALSE
  ))
  if (!exists(
    "riskmetric_spike_select_packages", envir = helpers, inherits = FALSE
  )) return()
  installed <- spike_installed_matrix(
    c("beta", "alpha", "alpha", "gamma"),
    c("2.0.0", "1.0.0", "9.0.0", "3.0.0")
  )

  selected <- helpers$riskmetric_spike_select_packages(installed, 3L)

  expect_identical(selected$Package, c("alpha", "beta", "gamma"))
  expect_identical(selected$Version, c("1.0.0", "2.0.0", "3.0.0"))
})

test_that("riskmetric spike rejects an insufficient distinct package set", {
  helpers <- load_spike_helpers()
  expect_true(exists(
    "riskmetric_spike_select_packages", envir = helpers, inherits = FALSE
  ))
  if (!exists(
    "riskmetric_spike_select_packages", envir = helpers, inherits = FALSE
  )) return()
  installed <- spike_installed_matrix(
    c("alpha", "alpha", "beta"), c("1.0.0", "9.0.0", "2.0.0")
  )

  expect_error(
    helpers$riskmetric_spike_select_packages(installed, 3L),
    "requested 3 packages but only 2 distinct"
  )
})

test_that("riskmetric spike rejects a cold assessment package mismatch", {
  helpers <- load_spike_helpers()
  expect_true(exists(
    "riskmetric_spike_validate_results", envir = helpers, inherits = FALSE
  ))
  if (!exists(
    "riskmetric_spike_validate_results", envir = helpers, inherits = FALSE
  )) return()
  installed <- spike_installed_matrix(
    c("alpha", "beta"), c("1.0.0", "2.0.0")
  )
  selected <- helpers$riskmetric_spike_select_packages(installed, 2L)
  cold <- spike_assessment("alpha")
  hot <- spike_assessment(c("alpha", "beta"))

  expect_error(
    helpers$riskmetric_spike_validate_results(cold, hot, selected),
    "cold assessment packages do not match"
  )
})

test_that("riskmetric spike rejects duplicate hot assessment packages", {
  helpers <- load_spike_helpers()
  expect_true(exists(
    "riskmetric_spike_validate_results", envir = helpers, inherits = FALSE
  ))
  if (!exists(
    "riskmetric_spike_validate_results", envir = helpers, inherits = FALSE
  )) return()
  installed <- spike_installed_matrix(
    c("alpha", "beta"), c("1.0.0", "2.0.0")
  )
  selected <- helpers$riskmetric_spike_select_packages(installed, 2L)
  cold <- spike_assessment(c("alpha", "beta"))
  hot <- spike_assessment(c("alpha", "alpha"))

  expect_error(
    helpers$riskmetric_spike_validate_results(cold, hot, selected),
    "hot assessment packages do not match"
  )
})

test_that("riskmetric smoke workflow has read-only contents permission", {
  workflow_path <- spike_source_file(
    ".github", "workflows", "riskmetric-smoke.yml"
  )
  skip_if_not(file.exists(workflow_path), "workflow is excluded from built packages")

  workflow <- yaml::read_yaml(workflow_path)

  expect_identical(workflow$permissions$contents, "read")
})

test_that("riskmetric smoke checkout does not persist credentials", {
  workflow_path <- spike_source_file(
    ".github", "workflows", "riskmetric-smoke.yml"
  )
  skip_if_not(file.exists(workflow_path), "workflow is excluded from built packages")
  workflow <- yaml::read_yaml(workflow_path)
  steps <- workflow$jobs[["riskmetric-smoke"]]$steps
  # match any checkout major so a version bump cannot silently drop this
  # security assertion (or fail it with an opaque subscript error)
  checkout <- Filter(
    function(step) is.character(step$uses) &&
      startsWith(step$uses, "actions/checkout@"),
    steps
  )

  expect_length(checkout, 1L)
  expect_identical(checkout[[1]]$with[["persist-credentials"]], FALSE)
})
