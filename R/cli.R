# CLI entry (FR-X-2/3). `inst/exec/avior` shims into main(); command
# functions signal avior_error for execution problems (exit 2); business
# failures (check red) map to exit 1 in the command handlers themselves.

parse_argv <- function(argv) {
  fmt <- "text"
  i <- which(argv == "--format")
  if (length(i) > 1) avior_abort("--format given more than once")
  if (length(i) == 1) {
    if (i == length(argv)) avior_abort("--format requires a value (text|json)")
    fmt <- argv[i + 1]
    if (!fmt %in% c("text", "json")) {
      avior_abort(paste0("unsupported --format `", fmt, "` (expected text|json)"))
    }
    argv <- argv[-c(i, i + 1)]
  }
  list(command = if (length(argv)) argv[1] else NA_character_,
       args = if (length(argv) > 1) argv[-1] else character(0),
       format = fmt)
}

emit_json <- function(x) {
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", pretty = 2), "\n", sep = "")
}

run_command <- function(opts) {
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
      incomplete <- isFALSE(inv$scan$complete)
      list(command = "scan",
           # an incomplete scan is a business failure here and now, not a
           # property deferred to `check` in a later PR (FR-SCAN-3)
           status = if (incomplete) "incomplete" else "ok",
           lockfile = inv$lockfile,
           summary = unclass(inv$summary),
           skipped_files = if (incomplete) {
             as.character(unlist(inv$scan$skipped_files))
           } else {
             character(0)
           })
    },
    avior_abort(paste0("unknown command: ", opts$command, " (expected: init|scan)"))
  )
}

main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  opts <- list(command = if (length(argv)) argv[1] else NA_character_,
               format = if ("json" %in% argv) "json" else "text")

  # Every failure — avior_error or unexpected — must map to exit 2 (FR-X-3):
  # a CI gate reading exit 1 would misread a crash as "validation failed".
  result <- tryCatch(
    {
      opts <- parse_argv(argv)
      run_command(opts)
    },
    avior_error = function(e) e,
    error = function(e) {
      structure(class = c("avior_unexpected_error", "avior_error",
                          "error", "condition"),
                list(message = paste0("unexpected error: ", conditionMessage(e)),
                     call = NULL))
    }
  )

  if (inherits(result, "avior_error")) {
    if (identical(opts$format, "json")) {
      emit_json(list(command = opts$command, status = "error",
                     message = conditionMessage(result)))
    } else {
      cli::cli_alert_danger(conditionMessage(result))
    }
    return(invisible(2L))
  }

  # business failure (e.g. an incomplete scan) -> exit 1; success -> 0
  exit_code <- if (identical(result$status, "ok")) 0L else 1L

  if (identical(opts$format, "json")) {
    emit_json(result)
    return(invisible(exit_code))
  }

  if (identical(result$command, "scan")) {
    s <- result$summary
    msg <- paste0(
      "scan: ", s$total, " packages (", s$direct, " direct, ",
      s$transitive, " transitive); ", s$in_scope_assessed, " in scope, ",
      s$recommended_exempt, " exempt, ", s$force_included, " force-included")
    if (identical(result$status, "incomplete")) {
      cli::cli_alert_danger(paste0(
        msg, "\nscan INCOMPLETE -- could not parse: ",
        paste(result$skipped_files, collapse = ", "),
        " (packages referenced only there are missing; fix and re-run)"))
    } else {
      cli::cli_alert_success(msg)
    }
  } else if (identical(result$command, "init")) {
    cli::cli_alert_success(paste0(
      "init: ", length(result$created), " created, ",
      length(result$skipped), " already present (kept)"))
  }
  invisible(exit_code)
}
