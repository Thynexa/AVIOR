# avior scan — dependency identification and classification (FR-SCAN-1..5).
# Writes <validation>/inventory.yml per PRD 6.1; package rows are flow maps
# in C-locale name order (FR-X-7), matching the frozen example layout.

# Inventory ownership across rescans (#26): inventory.yml is a GENERATED
# artifact owned by `avior scan` — rescans rewrite it wholesale. The one
# supported human annotation is the per-package `note:` field (present in
# the frozen M0 example, PRD 6.1): a rescan carries notes over by package
# name, so they survive regeneration; a note whose package left the
# dependency source disappears with its row. Any OTHER hand-added key is
# unsupported and is discarded — but never silently (FR-SCAN-4 spirit):
# the rescan warns, naming the field and the durable home for substantive
# human input, the decision records (rationale/use_statement, PRD 6.3).
INVENTORY_PACKAGE_KEYS <- c("name", "version", "classification", "role",
                            "in_scope", "source", "overridden",
                            "override_source", "note")

# name -> note map from a previous inventory; only well-formed notes
# (scalar non-empty strings on named rows) are carried over.
inventory_notes <- function(prev) {
  notes <- list()
  if (!is.list(prev) || !is.list(prev$packages)) return(notes)
  for (p in prev$packages) {
    if (is.list(p) &&
        is.character(p$name) && length(p$name) == 1 && nzchar(p$name) &&
        is.character(p$note) && length(p$note) == 1 && !is.na(p$note) &&
        nzchar(p$note)) {
      notes[[p$name]] <- p$note
    }
  }
  notes
}

warn_discarded_annotations <- function(prev) {
  if (!is.list(prev) || !is.list(prev$packages)) return(invisible())
  extra <- character(0)
  for (p in prev$packages) {
    if (!is.list(p)) next
    unknown <- setdiff(names(p), INVENTORY_PACKAGE_KEYS)
    if (length(unknown) > 0) {
      extra <- c(extra, paste0(
        if (is.character(p$name) && length(p$name) == 1) p$name else "<unnamed>",
        " (", paste(sort_c(unknown), collapse = ", "), ")"))
    }
  }
  if (length(extra) > 0) {
    warning(paste0(
      "avior scan: inventory.yml is a generated artifact and is rewritten ",
      "on every scan; unsupported hand-added field(s) are being discarded: ",
      paste(extra, collapse = "; "),
      ". Keep per-package remarks in the supported `note:` field, and ",
      "substantive human input in the decision records ",
      "(validation/decisions/<package>.yml)."), call. = FALSE)
  }
  invisible()
}

avior_scan <- function(root = ".") {
  cfg <- avior_config_load(root)

  out <- file.path(cfg$paths$validation, "inventory.yml")
  prev <- if (file.exists(out)) {
    tryCatch(read_yaml_file(out), error = function(e) NULL)
  }
  notes <- inventory_notes(prev)

  dep_src <- resolve_dep_source(root, cfg$scope$lockfile)
  lock <- classify_packages(dep_src$read(), cfg)

  direct <- if (identical(cfg$scope$intended_for_use, "explicit")) {
    n <- length(cfg$scope$include)
    data.frame(package = cfg$scope$include,
               file = rep("avior.yml scope.include", n),
               line = rep(NA_integer_, n),
               stringsAsFactors = FALSE)
  } else {
    scan_direct_calls(root, exclude_dirs = c(cfg$project$validation_dir,
                                             "renv", "packrat"))
  }

  # A human override that silently no-ops (typo, package since removed from
  # the lockfile) is a trust defect for an audit tool (FR-SCAN-4).
  unknown <- setdiff(c(cfg$scope$include, cfg$scope$exclude), lock$name)
  if (length(unknown) > 0) {
    warning(paste0("avior scan: scope.include/exclude reference packages ",
                   "not present in the lockfile: ",
                   paste(sort_c(unknown), collapse = ", ")),
            call. = FALSE)
  }

  entries <- lapply(seq_len(nrow(lock)), function(i) {
    name <- lock$name[i]
    classification <- lock$classification[i]
    hit <- direct[direct$package == name, , drop = FALSE]
    role <- if (nrow(hit) > 0) "direct" else "transitive"

    src <- if (role == "direct") {
      if (is.na(hit$line[1])) hit$file[1] else paste0(hit$file[1], ":", hit$line[1])
    } else {
      transitive_source(lock, name, default = dep_src$path)
    }

    default_in_scope <- role == "direct" && classification %in% c("contributed", "custom")
    in_scope <- default_in_scope
    overridden <- FALSE
    override_source <- NULL
    if (name %in% cfg$scope$include && !default_in_scope) {
      in_scope <- TRUE
      overridden <- TRUE
      override_source <- "avior.yml scope.include"
    }
    if (name %in% cfg$scope$exclude) {
      overridden <- in_scope || default_in_scope
      in_scope <- FALSE
      if (overridden) override_source <- "avior.yml scope.exclude"
    }

    entry <- list(
      name = name,
      version = lock$version[i],
      classification = classification,
      role = role,
      in_scope = in_scope,
      source = src
    )
    if (overridden) {
      entry$overridden <- TRUE
      entry$override_source <- override_source
    }
    # the supported human annotation survives the rescan (#26); field order
    # matches the frozen example (note last)
    if (!is.null(notes[[name]])) {
      entry$note <- notes[[name]]
    }
    yaml_flow(entry)
  })

  in_scope_flags <- vapply(entries, function(e) isTRUE(e$in_scope), logical(1))
  roles <- vapply(entries, function(e) e$role, character(1))
  classes <- vapply(entries, function(e) e$classification, character(1))
  forced <- vapply(entries, function(e)
    isTRUE(e$overridden) && identical(e$override_source, "avior.yml scope.include"),
    logical(1))

  # Files that could not be parsed are a SCOPE GAP: a package referenced only
  # there is silently missed. Persist that into the git-tracked inventory (a
  # transient console warning is not auditable) so `check` can gate on it
  # (FR-SCAN-3). Recorded in C-locale path order for determinism.
  skipped <- attr(direct, "skipped")
  skipped <- if (length(skipped) > 0) sort_c(skipped) else character(0)

  inventory <- list(
    avior = 1L,
    generated_by = "avior scan",
    # `path` records which source produced this inventory (renv.lock or the
    # DESCRIPTION fallback, FR-SCAN-1); the hash is the drift baseline
    lockfile = list(path = dep_src$path, sha256 = sha256_file(dep_src$file)),
    packages = entries,
    summary = yaml_flow(list(
      total = nrow(lock),
      direct = sum(roles == "direct"),
      transitive = sum(roles == "transitive"),
      in_scope_assessed = sum(in_scope_flags),
      recommended_exempt = sum(classes %in% c("base", "recommended") & !in_scope_flags),
      force_included = sum(forced)
    ))
  )

  # Only present when the scan could NOT read everything: absence means a
  # complete scan, so a clean project's inventory stays byte-identical.
  if (length(skipped) > 0) {
    inventory$scan <- list(complete = FALSE, skipped_files = yaml_seq(skipped))
  }

  warn_discarded_annotations(prev)
  write_yaml_canonical(inventory, out)
  invisible(inventory)
}
