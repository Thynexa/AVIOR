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
  if (is.null(pkgs)) {
    avior_abort(paste0(path, ": no Packages section (is this a renv.lock?)"))
  }
  df <- data.frame(
    name = vapply(pkgs, function(p) p$Package %||% "", character(1)),
    version = vapply(pkgs, function(p) p$Version %||% "", character(1)),
    source = vapply(pkgs, function(p) p$Source %||% "", character(1)),
    repository = vapply(pkgs, function(p) p$Repository %||% "", character(1)),
    priority = vapply(pkgs, function(p) p$Priority %||% "", character(1)),
    remote_org = vapply(pkgs, function(p) p$RemoteUsername %||% "", character(1)),
    remote_repo = vapply(pkgs, function(p) p$RemoteRepo %||% "", character(1)),
    stringsAsFactors = FALSE
  )
  if (any(!nzchar(df$name))) avior_abort(paste0(path, ": package entry without a name"))
  # provenance column used by the DESCRIPTION fallback; empty for renv rows
  df$declared_in <- rep("", nrow(df))
  df$requirements <- I(lapply(pkgs, function(p) as.character(unlist(p$Requirements))))
  df <- df[order_c(df$name), , drop = FALSE]
  rownames(df) <- NULL
  attr(df, "r_version") <- lock$R$Version %||% NA_character_
  df
}

# FR-SCAN-1 fallback: a package project without renv still declares its
# dependency surface in DESCRIPTION (Depends/Imports/LinkingTo). This source
# carries no pinned versions, no repository provenance and no transitive
# closure — those fields stay empty rather than being guessed, and the
# inventory records DESCRIPTION as its source so downstream consumers can
# tell the two apart.
read_description_deps <- function(path) {
  if (!file.exists(path)) {
    avior_abort(paste0("DESCRIPTION not found: ", path))
  }
  dcf <- tryCatch(read.dcf(path), error = function(e) {
    avior_abort(paste0("cannot parse ", path, ": ", conditionMessage(e)))
  })
  if (nrow(dcf) < 1 || !"Package" %in% colnames(dcf) ||
      is.na(dcf[1, "Package"]) || !nzchar(dcf[1, "Package"])) {
    avior_abort(paste0(path, ": not a package DESCRIPTION (no Package field)"))
  }

  # FR-SCAN-3: keep the declaring field per package — "an unused Imports
  # dependency" and "a LinkingTo dependency" are different provenance facts.
  # Fields are parsed in canonical order, so a package declared in several
  # fields gets a deterministic joined record (e.g. "Depends+Imports").
  declared <- list()
  bad <- character(0)
  for (field in intersect(c("Depends", "Imports", "LinkingTo"),
                          colnames(dcf))) {
    value <- dcf[1, field]
    if (is.na(value)) next
    raw <- unlist(strsplit(value, ",", fixed = TRUE))
    # strip version constraints ("jsonlite (>= 1.8.0)") and whitespace; the
    # constraint is a range, not a pinned version — recording it as `version`
    # would fabricate a precision the source does not have. DCF continuation
    # lines keep their newlines, so collapse all whitespace first.
    raw <- gsub("[[:space:]]+", " ", raw)
    names_clean <- trimws(sub("\\(.*$", "", raw))
    names_clean <- setdiff(names_clean[nzchar(names_clean)], "R")
    bad <- c(bad, names_clean[!grepl("^[A-Za-z][A-Za-z0-9.]*$", names_clean)])
    for (nm in unique(names_clean)) {
      declared[[nm]] <- unique(c(declared[[nm]], field))
    }
  }
  if (length(bad) > 0) {
    avior_abort(paste0(path, ": malformed dependency name(s): ",
                       paste(unique(bad), collapse = ", ")))
  }

  n <- length(declared)
  df <- data.frame(
    name = names(declared) %||% character(0),
    version = rep("", n),
    source = rep("", n),
    repository = rep("", n),
    priority = rep("", n),
    remote_org = rep("", n),
    remote_repo = rep("", n),
    declared_in = vapply(declared, paste, character(1), collapse = "+"),
    stringsAsFactors = FALSE
  )
  df$requirements <- I(rep(list(character(0)), n))
  df <- df[order_c(df$name), , drop = FALSE]
  rownames(df) <- NULL
  attr(df, "r_version") <- NA_character_
  df
}

# Dependency-source resolution (FR-SCAN-1): the configured lockfile is
# authoritative when present; a package project without renv falls back to
# DESCRIPTION at the project root. Fails closed when neither exists.
# `path` is the project-relative name recorded in the inventory.
resolve_dep_source <- function(root, lockfile) {
  lock_path <- file.path(root, lockfile)
  if (file.exists(lock_path)) {
    return(list(path = lockfile, file = lock_path,
                read = function() read_renv_lock(lock_path)))
  }
  desc_path <- file.path(root, "DESCRIPTION")
  if (file.exists(desc_path)) {
    return(list(path = "DESCRIPTION", file = desc_path,
                read = function() read_description_deps(desc_path)))
  }
  avior_abort(paste0("lockfile not found: ", lock_path,
                     " (and no DESCRIPTION fallback at ", desc_path, ")"))
}

# Provenance for a transitive package: the first (C-order) lockfile package
# that lists it in Requirements, e.g. "lme4 Requirements"; falls back to
# the dependency source file when no parent is recorded.
transitive_source <- function(lock, pkg, default = "renv.lock") {
  has <- vapply(seq_len(nrow(lock)), function(i) pkg %in% lock$requirements[[i]],
                logical(1))
  parents <- lock$name[has & lock$name != pkg]
  if (length(parents) == 0) return(default)
  paste0(sort_c(parents)[1], " Requirements")
}

`%||%` <- function(a, b) if (is.null(a)) b else a

glob_match <- function(globs, value) {
  if (length(globs) == 0 || !nzchar(value)) return(FALSE)
  any(vapply(utils::glob2rx(globs), function(rx) grepl(rx, value), logical(1)))
}

classify_packages <- function(lock, config) {
  org_globs <- config$scope$custom_orgs
  lock$classification <- vapply(seq_len(nrow(lock)), function(i) {
    # custom detection first: a GitHub fork of `survival` is the org's own
    # build, not the R-distribution package — source beats name (FR-SCAN-2)
    org <- lock$remote_org[i]
    repo <- lock$remote_repo[i]
    remote <- if (nzchar(org) && nzchar(repo)) paste0(org, "/", repo) else ""
    if (lock$source[i] %in% NON_REPOSITORY_SOURCES ||
        glob_match(org_globs, remote) ||
        glob_match(org_globs, org)) {
      return("custom")
    }
    # then the R-distribution priority field, falling back to vendored sets
    name <- lock$name[i]
    if (identical(lock$priority[i], "base") || name %in% BASE_PACKAGES) {
      return("base")
    }
    if (identical(lock$priority[i], "recommended") || name %in% RECOMMENDED_PACKAGES) {
      return("recommended")
    }
    "contributed"
  }, character(1))
  lock
}
