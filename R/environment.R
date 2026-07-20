# Environment fingerprinting for evidence bundles (FR-BUNDLE-5).
# Everything machine-varying funnels through the single capture_session()
# binding so golden tests can mock one seam and keep bundle bytes stable.

capture_session <- function() {
  si <- utils::sessionInfo()
  list(
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    lc_collate = Sys.getlocale("LC_COLLATE"),
    blas = si$BLAS %||% "",
    lapack = si$LAPACK %||% "",
    session_text = paste(utils::capture.output(print(si)), collapse = "\n")
  )
}

# A container image digest is not introspectable from inside the container;
# record it when the runner discloses it (CI can export the env var),
# otherwise an honest null (FR-BUNDLE-5).
container_digest <- function() {
  v <- Sys.getenv("AVIOR_CONTAINER_DIGEST", unset = "")
  if (nzchar(v)) v else NULL
}

# Repository provenance from the renv.lock snapshot, including the PPM
# snapshot date when the URL pins one; [] for DESCRIPTION-fallback projects
# (they carry no repository provenance, and guessing would be fabrication).
repositories_from_lockfile <- function(lock_path) {
  if (!file.exists(lock_path)) return(list())
  lock <- tryCatch(jsonlite::fromJSON(lock_path, simplifyVector = FALSE),
                   error = function(e) NULL)
  repos <- lock$R$Repositories
  if (is.null(repos)) return(list())
  lapply(repos, function(r) {
    url <- r$URL %||% ""
    snapshot <- if (grepl("([0-9]{4}-[0-9]{2}-[0-9]{2})", url)) {
      regmatches(url, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", url))
    } else {
      NULL
    }
    list(name = r$Name %||% "", url = url, snapshot = snapshot)
  })
}

# The environment.json model. `"unknown"` (never an omitted key) when a
# fact is not observable — an absent key is indistinguishable from "not
# collected" under audit (FR-BUNDLE-5).
capture_environment <- function(session, generated_at, inventory, scores,
                                cfg, dep_src_file, summary_counts) {
  or_unknown <- function(v) {
    if (is.character(v) && length(v) == 1 && nzchar(v)) v else "unknown"
  }
  engine <- if (!is.null(scores)) {
    list(id = scores$engine$id, version = scores$engine$version)
  } else {
    list(id = cfg$policy$engine, version = NULL)
  }
  list(
    avior_version = avior_version(),
    generated_at = generated_at,
    r_version = or_unknown(session$r_version),
    platform = or_unknown(session$platform),
    repositories = repositories_from_lockfile(dep_src_file),
    lockfile = list(path = inventory$lockfile$path,
                    sha256 = inventory$lockfile$sha256),
    engine = engine,
    locale = list(LC_COLLATE = or_unknown(session$lc_collate)),
    blas = or_unknown(session$blas),
    lapack = or_unknown(session$lapack),
    container = container_digest(),
    session_info = "session-info.txt",
    package_count = summary_counts
  )
}
