# avior scan — dependency identification and classification (FR-SCAN-1..5).
# Writes <validation>/inventory.yml per PRD 6.1; package rows are flow maps
# in C-locale name order (FR-X-7), matching the frozen example layout.

avior_scan <- function(root = ".") {
  cfg <- avior_config_load(root)

  lock_path <- file.path(root, cfg$scope$lockfile)
  lock <- classify_packages(read_renv_lock(lock_path), cfg)

  direct <- if (identical(cfg$scope$intended_for_use, "explicit")) {
    data.frame(package = cfg$scope$include,
               file = "avior.yml scope.include", line = NA_integer_,
               stringsAsFactors = FALSE)
  } else {
    scan_direct_calls(root, exclude_dirs = c(cfg$project$validation_dir,
                                             "renv", "packrat"))
  }

  entries <- lapply(seq_len(nrow(lock)), function(i) {
    name <- lock$name[i]
    classification <- lock$classification[i]
    hit <- direct[direct$package == name, , drop = FALSE]
    role <- if (nrow(hit) > 0) "direct" else "transitive"

    src <- if (role == "direct") {
      if (is.na(hit$line[1])) hit$file[1] else paste0(hit$file[1], ":", hit$line[1])
    } else {
      transitive_source(lock, name)
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
    yaml_flow(entry)
  })

  in_scope_flags <- vapply(entries, function(e) isTRUE(e$in_scope), logical(1))
  roles <- vapply(entries, function(e) e$role, character(1))
  classes <- vapply(entries, function(e) e$classification, character(1))
  forced <- vapply(entries, function(e)
    isTRUE(e$overridden) && identical(e$override_source, "avior.yml scope.include"),
    logical(1))

  inventory <- list(
    avior = 1L,
    generated_by = "avior scan",
    lockfile = list(path = cfg$scope$lockfile, sha256 = sha256_file(lock_path)),
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

  out <- file.path(cfg$paths$validation, "inventory.yml")
  write_yaml_canonical(inventory, out)
  invisible(inventory)
}
