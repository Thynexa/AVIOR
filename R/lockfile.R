# renv.lock parsing (FR-SCAN-1) and package classification (FR-SCAN-2).

# Vendored constants: base/recommended sets are fixed by the R distribution
# and stable across releases; vendoring keeps classification identical on
# machines where these packages are not locally installed.
BASE_PACKAGES <- c(
  "base", "compiler", "datasets", "grDevices", "graphics", "grid",
  "methods", "parallel", "splines", "stats", "stats4", "tcltk",
  "tools", "translations", "utils"
)

RECOMMENDED_PACKAGES <- c(
  "boot", "class", "cluster", "codetools", "foreign", "KernSmooth",
  "lattice", "MASS", "Matrix", "mgcv", "nlme", "nnet", "rpart",
  "spatial", "survival"
)

# renv Source values that mean "not a public repository" -> custom (PRD 6.2
# scope.custom_orgs adds org-glob matching on top).
NON_REPOSITORY_SOURCES <- c(
  "GitHub", "GitLab", "Bitbucket", "Local", "Remote", "git2r", "URL"
)

read_renv_lock <- function(path) {
  if (!file.exists(path)) {
    avior_abort(paste0("lockfile not found: ", path))
  }
  lock <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) avior_abort(paste0("cannot parse ", path, ": ", conditionMessage(e)))
  )
  pkgs <- lock$Packages
  if (is.null(pkgs) || length(pkgs) == 0) {
    avior_abort(paste0(path, ": no Packages section (is this a renv.lock?)"))
  }
  df <- data.frame(
    name = vapply(pkgs, function(p) p$Package %||% "", character(1)),
    version = vapply(pkgs, function(p) p$Version %||% "", character(1)),
    source = vapply(pkgs, function(p) p$Source %||% "", character(1)),
    repository = vapply(pkgs, function(p) p$Repository %||% "", character(1)),
    remote_org = vapply(pkgs, function(p) p$RemoteUsername %||% "", character(1)),
    remote_repo = vapply(pkgs, function(p) p$RemoteRepo %||% "", character(1)),
    stringsAsFactors = FALSE
  )
  if (any(!nzchar(df$name))) avior_abort(paste0(path, ": package entry without a name"))
  df <- df[order_c(df$name), , drop = FALSE]
  rownames(df) <- NULL
  attr(df, "r_version") <- lock$R$Version %||% NA_character_
  df
}

`%||%` <- function(a, b) if (is.null(a)) b else a

glob_match <- function(globs, value) {
  if (length(globs) == 0 || !nzchar(value)) return(FALSE)
  any(vapply(utils::glob2rx(globs), function(rx) grepl(rx, value), logical(1)))
}

classify_packages <- function(lock, config) {
  org_globs <- config$scope$custom_orgs
  lock$classification <- vapply(seq_len(nrow(lock)), function(i) {
    name <- lock$name[i]
    if (name %in% BASE_PACKAGES) return("base")
    if (name %in% RECOMMENDED_PACKAGES) return("recommended")
    remote <- paste0(lock$remote_org[i], "/", lock$remote_repo[i])
    if (lock$source[i] %in% NON_REPOSITORY_SOURCES ||
        glob_match(org_globs, remote) ||
        glob_match(org_globs, lock$remote_org[i])) {
      return("custom")
    }
    "contributed"
  }, character(1))
  lock
}
