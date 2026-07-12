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
      list(command = "scan", status = "ok",
           lockfile = inv$lockfile,
           summary = unclass(inv$summary))
    },
    assess = {
      deep <- "--deep" %in% opts$args
      offline <- "--offline" %in% opts$args
      i <- which(opts$args == "--only")
      if (length(i) > 1) avior_abort("--only given more than once")
      only <- NULL
      if (length(i) == 1) {
        if (i == length(opts$args)) avior_abort("--only requires a package name")
        only <- opts$args[i + 1]
      }
      s <- avior_assess(".", only = only, deep = deep,
                        network_available = !offline)
      list(command = "assess", status = "ok",
           engine = unclass(s$engine), run = unclass(s$run),
           packages = length(s$packages),
           na_metrics = as.character(unclass(s$na_metrics)))
    },
    review = {
      r <- avior_review(".")
      # review reports but does not gate (check does); "findings" instead of
      # "ok" so JSON consumers cannot mistake a flagged state for a clean one
      list(command = "review",
           status = if (length(r$findings) > 0) "findings" else "ok",
           stubs_created = r$stubs_created, findings = r$findings)
    },
    check = {
      res <- avior_check(".")
      c(list(command = "check"), res)
    },
    avior_abort(paste0("unknown command: ", opts$command,
                       " (expected: init|scan|assess|review|check)"))
  )
}

print_findings <- function(findings) {
  by_pkg <- split(findings, vapply(findings, function(f) f$package, character(1)))
  for (pkg in sort_c(names(by_pkg))) {
    cli::cli_alert_danger(pkg)
    for (f in by_pkg[[pkg]]) {
      cli::cli_bullets(c(" " = paste0("[", f$type, "] ", f$message),
                         ">" = paste0("fix: ", f$fix %||% "-")))
    }
  }
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
    avior_na_error = function(e) e,
    avior_error = function(e) e,
    error = function(e) {
      structure(class = c("avior_unexpected_error", "avior_error",
                          "error", "condition"),
                list(message = paste0("unexpected error: ", conditionMessage(e)),
                     call = NULL))
    }
  )

  if (inherits(result, "avior_error")) {
    # na_action: fail is a policy outcome, not a crash -> business exit 1
    code <- if (inherits(result, "avior_na_error")) 1L else 2L
    if (identical(opts$format, "json")) {
      emit_json(list(command = opts$command,
                     status = if (code == 1L) "fail" else "error",
                     message = conditionMessage(result)))
    } else {
      cli::cli_alert_danger(conditionMessage(result))
    }
    return(invisible(code))
  }

  exit_code <- if (identical(result$command, "check") &&
                   identical(result$status, "fail")) 1L else 0L

  if (identical(opts$format, "json")) {
    emit_json(result)
    return(invisible(exit_code))
  } else {
    if (identical(result$command, "check")) {
      if (identical(result$status, "pass")) {
        cli::cli_alert_success("check: all gates green")
      } else {
        cli::cli_alert_danger(paste0("check: ", length(result$findings),
                                     " finding(s)"))
        print_findings(result$findings)
      }
    } else if (identical(result$command, "assess")) {
      cli::cli_alert_success(paste0(
        "assess: ", result$packages, " package(s) scored with ",
        result$engine$id, " ", result$engine$version,
        if (length(result$na_metrics) > 0)
          paste0(" (NA metrics: ", paste(result$na_metrics, collapse = ", "), ")")
        else ""))
    } else if (identical(result$command, "review")) {
      cli::cli_alert_success(paste0(
        "review: ", length(result$stubs_created), " stub(s) created, ",
        length(result$findings), " finding(s)"))
      if (length(result$findings) > 0) print_findings(result$findings)
    } else if (identical(result$command, "scan")) {
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
  invisible(exit_code)
}
