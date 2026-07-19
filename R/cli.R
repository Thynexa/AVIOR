# exec/avior entry (FR-X-2/3). Top-level `exec/avior` shims into main(); command
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

# I() keeps a field a JSON array regardless of length: with auto_unbox a bare
# length-1 vector becomes a scalar, so a collection field would change type
# by element count (a machine consumer can't parse it stably). Scalars
# (command/status/...) stay unboxed.
json_array <- function(x) I(as.character(x))

avior_command_names <- function() c("init", "scan", "assess", "review", "check")

avior_command_hint <- function() paste(avior_command_names(), collapse = "|")

avior_version <- function() as.character(utils::packageVersion("avior"))

# Unknown/leftover arguments must not be silently ignored — a user believing
# `avior scan --deep` took effect is a trust defect. Commands consume their
# own flags; anything left is an execution error (exit 2).
reject_extra_args <- function(args, command) {
  if (length(args) > 0) {
    avior_abort(paste0(command, ": unexpected argument(s): ",
                       paste(args, collapse = " ")))
  }
}

run_command <- function(opts) {
  if (is.na(opts$command)) {
    avior_abort(paste0("no command given (expected: ", avior_command_hint(), ")"))
  }
  switch(
    opts$command,
    `--help` = {
      reject_extra_args(opts$args, "--help")
      list(
        command = "help", status = "ok", usage = "avior <command> [options]",
        commands = json_array(avior_command_names()),
        options = json_array(c("--format text|json", "--help", "--version"))
      )
    },
    `--version` = {
      reject_extra_args(opts$args, "--version")
      list(command = "version", status = "ok", version = avior_version())
    },
    init = {
      args <- opts$args
      ci <- NULL
      i <- which(args == "--ci")
      if (length(i) > 1) avior_abort("--ci given more than once")
      if (length(i) == 1) {
        if (i == length(args)) avior_abort("--ci requires a value (github|gitlab)")
        ci <- args[i + 1]
        args <- args[-c(i, i + 1)]
      }
      reject_extra_args(args, "init")
      res <- avior_init(".", ci = ci)
      list(command = "init", status = "ok",
           created = json_array(res$created), skipped = json_array(res$skipped))
    },
    scan = {
      reject_extra_args(opts$args, "scan")
      inv <- avior_scan(".")
      incomplete <- isFALSE(inv$scan$complete)
      list(command = "scan",
           # an incomplete scan is a business failure here and now, not a
           # property deferred to `check` in a later PR (FR-SCAN-3)
           status = if (incomplete) "incomplete" else "ok",
           lockfile = inv$lockfile,
           summary = unclass(inv$summary),
           skipped_files = json_array(if (incomplete) {
             unlist(inv$scan$skipped_files)
           } else {
             character(0)
           }))
    },
    assess = {
      # consume this command's own flags, then reject anything left over
      args <- opts$args
      deep <- "--deep" %in% args; args <- args[args != "--deep"]
      offline <- "--offline" %in% args; args <- args[args != "--offline"]
      only <- NULL
      i <- which(args == "--only")
      if (length(i) > 1) avior_abort("--only given more than once")
      if (length(i) == 1) {
        if (i == length(args)) avior_abort("--only requires a package name")
        only <- args[i + 1]
        args <- args[-c(i, i + 1)]
      }
      # FR-X-5: refresh_na defaults to TRUE (retry network-cause NA cache
      # entries when online); an explicit true|false value — not a bare
      # flag — so the mapping to avior_assess(refresh_na=) stays literal
      refresh_na <- TRUE
      i <- which(args == "--refresh-na")
      if (length(i) > 1) avior_abort("--refresh-na given more than once")
      if (length(i) == 1) {
        if (i == length(args)) avior_abort("--refresh-na requires a value (true|false)")
        val <- args[i + 1]
        if (!val %in% c("true", "false")) {
          avior_abort(paste0("unsupported --refresh-na `", val,
                             "` (expected true|false)"))
        }
        refresh_na <- identical(val, "true")
        args <- args[-c(i, i + 1)]
      }
      reject_extra_args(args, "assess")
      s <- avior_assess(".", only = only, deep = deep,
                        refresh_na = refresh_na,
                        network_available = !offline)
      list(command = "assess", status = "ok",
           engine = unclass(s$engine), run = unclass(s$run),
           packages = length(s$packages),
           na_metrics = json_array(unclass(s$na_metrics)))
    },
    review = {
      reject_extra_args(opts$args, "review")
      r <- avior_review(".")
      # review reports but does not gate (check does); "findings" instead of
      # "ok" so JSON consumers cannot mistake a flagged state for a clean one
      list(command = "review",
           status = if (length(r$findings) > 0) "findings" else "ok",
           stubs_created = json_array(r$stubs_created), findings = r$findings)
    },
    check = {
      reject_extra_args(opts$args, "check")
      res <- avior_check(".")
      c(list(command = "check"), res)
    },
    avior_abort(paste0("unknown command: ", opts$command,
                       " (expected: ", avior_command_hint(), ")"))
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

  # business failures (check fail, incomplete scan) -> exit 1; review reports
  # findings but does not gate, so its "findings" status stays exit 0
  exit_code <- if (identical(result$status, "fail") ||
                   identical(result$status, "incomplete")) 1L else 0L

  if (identical(opts$format, "json")) {
    emit_json(result)
    return(invisible(exit_code))
  }

  if (identical(result$command, "help")) {
    cat(result$usage, "\n", sep = "")
    cat("commands: ", paste(result$commands, collapse = " "), "\n", sep = "")
    cat("options: ", paste(result$options, collapse = " "), "\n", sep = "")
  } else if (identical(result$command, "version")) {
    cat("avior ", result$version, "\n", sep = "")
  } else if (identical(result$command, "check")) {
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
