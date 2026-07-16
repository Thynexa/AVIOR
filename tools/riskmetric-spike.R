library(avior)

n <- as.integer(Sys.getenv("AVIOR_SPIKE_PACKAGES", "5"))
if (length(n) != 1L || is.na(n) || n < 1L) {
  stop("AVIOR_SPIKE_PACKAGES must be a positive integer")
}

installed <- as.data.frame(installed.packages(), stringsAsFactors = FALSE)
installed <- installed[
  is.na(installed$Priority) & installed$Package != "avior",
]
installed <- installed[order(installed$Package), ]
installed <- installed[seq_len(min(n, nrow(installed))), ]

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
summary <- list(
  r = R.version.string,
  avior = as.character(utils::packageVersion("avior")),
  riskmetric = as.character(utils::packageVersion("riskmetric")),
  packages = nrow(installed),
  cold_seconds = unname(cold),
  hot_seconds = unname(hot),
  na_metrics = unclass(second$na_metrics)
)
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE), "\n")

stopifnot(cold <= 1800, hot <= 300)
