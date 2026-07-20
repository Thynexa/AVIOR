# avior verify — standalone bundle integrity verification (FR-VERIFY-1..3).
# Recomputes the SHA-256 of every file listed in MANIFEST.sha256 for a
# bundle directory or transport zip and reports missing/modified/malformed/
# duplicate/unexpected files. Runs WITHOUT project context: no avior.yml,
# no renv.lock, no assessment engine (FR-VERIFY-2) — an auditor needs only
# the bundle and this package.
#
# Trust boundary (PRD §5.8): the manifest proves the bundle's INTERNAL
# consistency only. Whoever can rewrite files can rewrite the manifest too;
# the anti-tamper anchor is external (the git commit, a QMS archive record,
# or an independent signature over the FR-VERIFY-3 anchor hash).

MANIFEST_NAME <- "MANIFEST.sha256"

verify_finding <- function(type, path, message, line = NULL,
                           expected = NULL, actual = NULL) {
  f <- list(type = type, path = path, message = message)
  if (!is.null(line)) f$line <- as.integer(line)
  if (!is.null(expected)) f$expected <- expected
  if (!is.null(actual)) f$actual <- actual
  f
}

# A relative path is safe when it cannot escape the bundle root or alias
# another entry: no absolute/drive-letter form, no backslashes, and no
# empty/"."/".." segments.
manifest_path_safe <- function(p) {
  if (!is.character(p) || length(p) != 1 || !nzchar(p)) return(FALSE)
  if (grepl("^/", p) || grepl("^[A-Za-z]:", p)) return(FALSE)
  if (grepl("\\", p, fixed = TRUE)) return(FALSE)
  segs <- strsplit(p, "/", fixed = TRUE)[[1]]
  length(segs) > 0 && !any(segs %in% c("", ".", ".."))
}

# Strict parse: "<64 lowercase hex><exactly two spaces><path>". Anything
# else is a typed `malformed` finding naming the line — a manifest this
# tool cannot read verbatim is a bundle that measurably fails verification
# (exit 1), not a crash.
verify_parse_manifest <- function(path) {
  txt <- readChar(path, file.size(path), useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f

  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  # a trailing newline (canonical form) yields no phantom last element with
  # strsplit; a missing trailing newline is tolerated on read
  hashes <- character(0)
  paths <- character(0)
  for (i in seq_along(lines)) {
    line <- lines[i]
    if (grepl("\r", line, fixed = TRUE)) {
      add(verify_finding("malformed", MANIFEST_NAME,
                         paste0("line ", i, ": CRLF line ending (canonical ",
                                "manifests are LF-only)"), line = i))
      next
    }
    if (!grepl("^[0-9a-f]{64}  [^ ]", line)) {
      add(verify_finding("malformed", MANIFEST_NAME,
                         paste0("line ", i, ": expected `<sha256>  <path>` ",
                                "(64 lowercase hex digits, two spaces, path)"),
                         line = i))
      next
    }
    p <- substring(line, 67)
    if (startsWith(p, "*")) {
      # GNU sha256sum binary-mode marker: `<hash> *<path>` — ambiguous
      # between a marker and a literal `*`-prefixed filename; fail closed.
      add(verify_finding("malformed", MANIFEST_NAME,
                         paste0("line ", i, ": binary-mode `*` marker (or a ",
                                "`*`-prefixed path) is not part of the ",
                                "canonical format"), line = i))
      next
    }
    if (identical(p, MANIFEST_NAME)) {
      add(verify_finding("malformed", MANIFEST_NAME,
                         paste0("line ", i, ": the manifest must not list ",
                                "itself"), line = i))
      next
    }
    if (!manifest_path_safe(p)) {
      add(verify_finding("malformed", MANIFEST_NAME,
                         paste0("line ", i, ": unsafe path `", p,
                                "` (absolute, drive-letter, backslash, or ",
                                "`..` segments are not allowed)"), line = i))
      next
    }
    if (p %in% paths) {
      add(verify_finding("duplicate", p,
                         paste0("line ", i, ": path listed more than once"),
                         line = i))
      next
    }
    hashes <- c(hashes, substring(line, 1, 64))
    paths <- c(paths, p)
  }

  if (length(paths) > 1 && !identical(paths, sort_c(paths))) {
    add(verify_finding("malformed", MANIFEST_NAME,
                       "entries are not in C-locale path order (the canonical form is path-sorted)"))
  }

  list(hashes = hashes, paths = paths, findings = findings)
}

verify_dir <- function(dir) {
  manifest <- file.path(dir, MANIFEST_NAME)
  if (!file.exists(manifest)) {
    avior_abort(paste0("not an avior bundle: no ", MANIFEST_NAME,
                       " found in ", dir))
  }
  parsed <- verify_parse_manifest(manifest)
  findings <- parsed$findings
  add <- function(f) findings[[length(findings) + 1L]] <<- f

  checked <- 0L
  for (i in seq_along(parsed$paths)) {
    p <- parsed$paths[i]
    target <- file.path(dir, p)
    if (!file.exists(target)) {
      add(verify_finding("missing", p, "listed in the manifest but absent"))
      next
    }
    actual <- sha256_file(target)
    checked <- checked + 1L
    if (!identical(actual, parsed$hashes[i])) {
      add(verify_finding("modified", p,
                         "content hash does not match the manifest",
                         expected = parsed$hashes[i], actual = actual))
    }
  }

  present <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  present <- gsub("\\", "/", present, fixed = TRUE)
  for (p in sort_c(setdiff(present, c(parsed$paths, MANIFEST_NAME)))) {
    add(verify_finding("unexpected", p,
                       "present in the bundle but not listed in the manifest"))
  }

  # deterministic output: fixed category order, C-locale path order within
  order_key <- c(malformed = 1L, duplicate = 2L, missing = 3L,
                 modified = 4L, unexpected = 5L)
  findings <- findings[order_c(
    vapply(findings, function(f) order_key[[f$type]], integer(1)),
    vapply(findings, function(f) f$path, character(1)),
    vapply(findings, function(f) f$line %||% 0L, integer(1)))]

  status <- if (length(findings) == 0) "pass" else "fail"
  list(
    status = status,
    files_checked = checked,
    # FR-VERIFY-3: the external anchor — record this next to the bundle
    # (git commit message, QMS record, signature) at archival time
    anchor = if (identical(status, "pass")) sha256_file(manifest) else NULL,
    findings = findings
  )
}

# Pre-extraction safety: entry names come from an untrusted archive. Reject
# anything that could land outside the extraction root or alias another
# entry; refusing to process a hostile archive is an execution error
# (exit 2), not a measured verification result.
verify_zip_entries <- function(zipfile) {
  listing <- tryCatch(
    utils::unzip(zipfile, list = TRUE),
    error = function(e) {
      avior_abort(paste0("cannot read zip archive ", zipfile, ": ",
                         conditionMessage(e)))
    },
    warning = function(w) {
      avior_abort(paste0("cannot read zip archive ", zipfile, ": ",
                         conditionMessage(w)))
    }
  )
  names <- listing$Name
  # EVERY entry name is validated before extraction — directory rows too:
  # a hostile directory name (`../escape/`, `C:\` ...) creates paths outside
  # the extraction root just as surely as a file entry would. Directories
  # carry a single trailing `/` which is stripped for the check.
  stripped <- sub("/$", "", names)
  for (p in stripped) {
    if (!manifest_path_safe(p)) {
      avior_abort(paste0("unsafe zip entry `", p, "` in ", zipfile,
                         " (absolute, drive-letter, backslash, or `..` ",
                         "paths are not allowed)"))
    }
    # Non-ASCII names are refused outright: NFC/NFD variants of the same
    # text are distinct entries on Linux but alias one path on default
    # macOS filesystems, and R has no dependency-free Unicode normalizer
    # to detect that collision deterministically. AVIOR transport zips
    # only ever contain ASCII bundle paths (R package names are ASCII);
    # anything else must be verified as a directory, where the filesystem
    # itself is the single source of truth.
    if (any(charToRaw(p) > as.raw(0x7F))) {
      avior_abort(paste0("non-ASCII zip entry `", p, "` in ", zipfile,
                         " (transport archives contain only ASCII bundle ",
                         "paths; extract manually and verify the directory ",
                         "instead)"))
    }
  }
  # Duplicates are rejected after ASCII case-folding, not just byte-equal:
  # `A` and `a` are distinct entries on Linux but alias the SAME file on
  # default macOS/Windows filesystems, so verification of such an archive
  # would depend on the host — fail closed instead. Directory rows join the
  # check so `x/` cannot alias a file `x` either.
  folded <- tolower(stripped)
  if (anyDuplicated(folded)) {
    dup <- stripped[duplicated(folded)][1]
    avior_abort(paste0("ambiguous zip archive ", zipfile, ": entry `", dup,
                       "` appears more than once (byte-identical or ",
                       "case-folded duplicate)"))
  }
  names[!grepl("/$", names)]   # content entries: directory rows carry none
}

verify_extract_zip <- function(zipfile, exdir) {
  entries <- verify_zip_entries(zipfile)
  # belt-and-braces: the internal unzip downgrades some path problems to
  # warnings and keeps extracting; after the pre-validation above any
  # remaining warning is unexpected, so treat it as a refusal (exit 2)
  withCallingHandlers(
    utils::unzip(zipfile, exdir = exdir, unzip = "internal",
                 setTimes = FALSE),
    warning = function(w) {
      avior_abort(paste0("cannot extract zip archive ", zipfile, ": ",
                         conditionMessage(w)))
    }
  )
  # layout: MANIFEST.sha256 at the archive root (bundle-dir zip) or inside
  # exactly one top-level directory (transport zip of the bundle dir)
  if (MANIFEST_NAME %in% entries) return(exdir)
  tops <- unique(vapply(strsplit(entries, "/", fixed = TRUE),
                        function(s) s[1], character(1)))
  if (length(tops) == 1 &&
      paste0(tops, "/", MANIFEST_NAME) %in% entries) {
    return(file.path(exdir, tops))
  }
  avior_abort(paste0("unsupported archive layout in ", zipfile, ": expected ",
                     MANIFEST_NAME, " at the root or inside a single ",
                     "top-level bundle directory"))
}

avior_verify <- function(bundle) {
  if (!is.character(bundle) || length(bundle) != 1 || !nzchar(bundle)) {
    avior_abort("verify: requires a bundle path (directory or zip)")
  }
  if (dir.exists(bundle)) {
    res <- verify_dir(bundle)
    return(c(list(bundle = bundle, source = "directory"), res))
  }
  if (!file.exists(bundle)) {
    avior_abort(paste0("bundle not found: ", bundle))
  }
  exdir <- tempfile("avior-verify-")
  dir.create(exdir)
  on.exit(unlink(exdir, recursive = TRUE, force = TRUE), add = TRUE)
  dir <- verify_extract_zip(bundle, exdir)
  res <- verify_dir(dir)
  c(list(bundle = bundle, source = "zip"), res)
}
