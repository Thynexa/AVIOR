riskmetric_spike_package_count <- function(value) {
  valid <- is.character(value) && length(value) == 1L && !is.na(value) &&
    grepl("^[1-9][0-9]*$", value)
  if (!valid) {
    stop("AVIOR_SPIKE_PACKAGES must be a positive integer")
  }
  count <- suppressWarnings(as.integer(value))
  if (is.na(count)) {
    stop("AVIOR_SPIKE_PACKAGES must be a positive integer")
  }
  count
}

riskmetric_spike_select_packages <- function(installed, n) {
  if (length(n) != 1L || is.na(n) || n < 1L || n != as.integer(n)) {
    stop("AVIOR_SPIKE_PACKAGES must be a positive integer")
  }
  installed <- as.data.frame(installed, stringsAsFactors = FALSE)
  installed <- installed[
    is.na(installed$Priority) & installed$Package != "avior",
    , drop = FALSE
  ]
  installed <- installed[
    order(installed$Package, method = "radix"),
    , drop = FALSE
  ]
  installed <- installed[!duplicated(installed$Package), , drop = FALSE]
  if (nrow(installed) < n) {
    stop(sprintf(
      "requested %d packages but only %d distinct contributed packages are installed",
      n, nrow(installed)
    ))
  }
  installed[seq_len(n), , drop = FALSE]
}

riskmetric_spike_validate_results <- function(first, second, selected) {
  expected <- as.character(selected$Package)
  validate <- function(result, label) {
    actual <- names(result$packages)
    valid <- length(actual) == length(expected) &&
      !anyDuplicated(actual) && setequal(actual, expected)
    if (!valid) {
      stop(paste0(
        label,
        " assessment packages do not match the selected distinct package set"
      ))
    }
    actual
  }
  validate(first, "cold")
  hot_packages <- validate(second, "hot")
  length(unique(hot_packages))
}

riskmetric_spike_main <- function() {
  library(avior)

  n <- riskmetric_spike_package_count(
    Sys.getenv("AVIOR_SPIKE_PACKAGES", "5")
  )
  installed <- riskmetric_spike_select_packages(installed.packages(), n)

  root <- tempfile("avior-riskmetric-spike-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  file.copy(
    system.file("templates", "avior.yml", package = "avior"),
    file.path(root, "validation", "avior.yml")
  )
  inventory <- list(
    avior = 1L,
    lockfile = list(path = "renv.lock", sha256 = "integration-spike"),
    packages = lapply(seq_len(nrow(installed)), function(i) {
      list(
        name = installed$Package[[i]],
        version = installed$Version[[i]],
        in_scope = TRUE
      )
    })
  )
  avior:::write_yaml_canonical(
    inventory, file.path(root, "validation", "inventory.yml")
  )

  cold <- system.time(first <- avior_assess(root))["elapsed"]
  hot <- system.time(second <- avior_assess(root))["elapsed"]
  package_count <- riskmetric_spike_validate_results(first, second, installed)
  summary <- list(
    r = R.version.string,
    avior = as.character(utils::packageVersion("avior")),
    riskmetric = as.character(utils::packageVersion("riskmetric")),
    packages = package_count,
    cold_seconds = unname(cold),
    hot_seconds = unname(hot),
    na_metrics = unclass(second$na_metrics)
  )
  cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")

  stopifnot(cold <= 1800, hot <= 300)
}

if (sys.nframe() == 0L) {
  riskmetric_spike_main()
}
