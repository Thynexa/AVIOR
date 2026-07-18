# Regenerate renv.lock as a native renv::snapshot() artifact (issue #28).
#
# The committed renv.lock predating this script was assembled from package
# DESCRIPTION metadata rather than snapshotted: entries carried no `Hash` or
# `Requirements` and embedded fields renv never writes (Author/Title/...).
# This script rebuilds it properly, in an environment WITH the dependency
# closure available (CRAN/RSPM access): it restores the closure from the
# existing lockfile into a private library, snapshots that library, checks
# the result is a well-formed renv artifact with an unchanged package set
# (a format fix must not become a dependency change), and verifies
# renv::restore() works from the regenerated file.
#
# Usage (from the repository root):
#   Rscript tools/regenerate-renv-lock.R            # regenerate + verify
#   Rscript tools/regenerate-renv-lock.R --check    # only validate the
#                                                   # committed lockfile shape
#
# The CI workflow .github/workflows/regenerate-renv-lock.yml runs this on
# demand (workflow_dispatch) and uploads the regenerated lockfile.

LOCKFILE <- "renv.lock"

# renv writes exactly these keys for a Repository-sourced record (plus
# Requirements/Hash); anything else in an entry is foreign metadata.
RENV_RECORD_KEYS <- c(
  "Package", "Version", "Source", "Type", "Repository", "OS_type",
  "Requirements", "Hash", "RemoteType", "RemoteHost", "RemoteUsername",
  "RemoteRepo", "RemoteRef", "RemoteSha", "RemoteSubdir", "RemoteUrl"
)

read_lock <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

lock_packages <- function(lock) sort(names(lock$Packages))

# Returns a character vector of problems (empty = native artifact shape).
lockfile_shape_problems <- function(lock) {
  problems <- character(0)
  for (name in names(lock$Packages)) {
    entry <- lock$Packages[[name]]
    if (is.null(entry$Hash)) {
      problems <- c(problems, paste0(name, ": no Hash"))
    }
    foreign <- setdiff(names(entry), RENV_RECORD_KEYS)
    if (length(foreign) > 0) {
      problems <- c(problems, paste0(
        name, ": foreign metadata (", paste(foreign, collapse = ", "), ")"))
    }
  }
  problems
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  if (!file.exists(LOCKFILE)) {
    stop("run this script from the repository root (renv.lock not found)")
  }
  old <- read_lock(LOCKFILE)

  if (identical(argv, "--check")) {
    problems <- lockfile_shape_problems(old)
    if (length(problems) == 0) {
      cat("renv.lock is a well-formed renv artifact\n")
      return(invisible(0L))
    }
    cat("renv.lock is NOT a native renv::snapshot() artifact:\n")
    cat(paste0("  - ", problems, collapse = "\n"), "\n")
    return(invisible(1L))
  }

  if (!requireNamespace("renv", quietly = TRUE)) {
    stop("the renv package is required (install.packages(\"renv\"))")
  }

  lib <- file.path(tempdir(), "renv-lock-lib")
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)

  # 1. install the pinned closure from the existing lockfile; restore() only
  #    needs Package/Version/Source, so it works from the pre-fix artifact
  cat("Restoring", length(old$Packages), "packages into", lib, "...\n")
  renv::restore(lockfile = LOCKFILE, library = lib, clean = FALSE,
                prompt = FALSE)

  # 2. snapshot that library: records Hash + Requirements, drops everything
  #    renv does not own
  cat("Snapshotting...\n")
  renv::snapshot(library = lib, lockfile = LOCKFILE, type = "all",
                 prompt = FALSE)

  # 3. a format fix must not become a dependency change
  new <- read_lock(LOCKFILE)
  removed <- setdiff(lock_packages(old), lock_packages(new))
  added <- setdiff(lock_packages(new), lock_packages(old))
  if (length(removed) > 0 || length(added) > 0) {
    stop(paste0("package set changed: removed [",
                paste(removed, collapse = ", "), "], added [",
                paste(added, collapse = ", "), "]"))
  }
  for (name in lock_packages(old)) {
    ov <- old$Packages[[name]]$Version
    nv <- new$Packages[[name]]$Version
    if (!identical(ov, nv)) {
      stop(paste0(name, ": version changed ", ov, " -> ", nv))
    }
  }
  problems <- lockfile_shape_problems(new)
  if (length(problems) > 0) {
    stop(paste0("regenerated lockfile is still malformed:\n  ",
                paste(problems, collapse = "\n  ")))
  }

  # 4. prove the regenerated artifact restores
  verify_lib <- file.path(tempdir(), "renv-lock-verify")
  dir.create(verify_lib, recursive = TRUE, showWarnings = FALSE)
  cat("Verifying renv::restore() from the regenerated lockfile...\n")
  renv::restore(lockfile = LOCKFILE, library = verify_lib, clean = FALSE,
                prompt = FALSE)

  cat("renv.lock regenerated:", length(new$Packages),
      "packages, all entries carry Hash; restore verified\n")
  invisible(0L)
}

if (sys.nframe() == 0L) {
  status <- main()
  quit(save = "no", status = if (is.numeric(status)) status else 0L)
}
