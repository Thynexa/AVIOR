# Shared helpers: hashing, classed errors, structured check findings.

sha256_file <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}

# Execution errors (FR-X-3 exit code 2). `class` may be a subclass such as
# "avior_config_error"; "avior_error" is always attached.
avior_abort <- function(msg, class = "avior_error") {
  stop(structure(
    class = unique(c(class, "avior_error", "error", "condition")),
    list(message = msg, call = sys.call(-1))
  ))
}

# Business findings (FR-X-3 exit code 1): one defect, attributable to a
# package, with a fix suggestion (NFR-8: every red light says how to fix it).
finding <- function(package, type, message, fix = NULL) {
  list(package = package, type = type, message = message, fix = fix)
}
