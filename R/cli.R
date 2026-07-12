# CLI entry (FR-X-2/3). `inst/exec/avior` shims into main(); command
# functions signal avior_error for execution problems (exit 2); business
# failures (check red) map to exit 1 in the command handlers themselves.

parse_argv <- function(argv) {
  fmt <- "text"
  i <- which(argv == "--format")
  if (length(i) == 1 && i < length(argv)) {
    fmt <- argv[i + 1]
    argv <- argv[-c(i, i + 1)]
  }
  list(command = if (length(argv)) argv[1] else NA_character_,
       args = if (length(argv) > 1) argv[-1] else character(0),
       format = fmt)
}

emit_json <- function(x) {
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = 2), "\n", sep = "")
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  opts <- parse_argv(argv)

  run <- function() {
    if (is.na(opts$command)) {
      avior_abort("no command given (expected: init|scan)")
    }
    switch(
      opts$command,
      init = {
        res <- avior_init(".")
        list(command = "init", status = "ok",
             created = res$created, skipped = res$skipped)
      },
      scan = {
        inv <- avior_scan(".")
        list(command = "scan", status = "ok",
             lockfile = inv$lockfile,
             summary = unclass(inv$summary))
      },
      avior_abort(paste0("unknown command: ", opts$command, " (expected: init|scan)"))
    )
  }

  result <- tryCatch(run(), avior_error = function(e) e)

  if (inherits(result, "avior_error")) {
    if (identical(opts$format, "json")) {
      emit_json(list(command = opts$command, status = "error",
                     message = conditionMessage(result)))
    } else {
      cli::cli_alert_danger(conditionMessage(result))
    }
    return(invisible(2L))
  }

  if (identical(opts$format, "json")) {
    emit_json(result)
  } else {
    if (identical(result$command, "scan")) {
      s <- result$summary
      cli::cli_alert_success(paste0(
        "scan: ", s$total, " packages (", s$direct, " direct, ",
        s$transitive, " transitive); ", s$in_scope_assessed, " in scope, ",
        s$recommended_exempt, " exempt, ", s$force_included, " force-included"))
    } else if (identical(result$command, "init")) {
      cli::cli_alert_success(paste0(
        "init: ", length(result$created), " created, ",
        length(result$skipped), " already present (kept)"))
    }
  }
  invisible(0L)
}
