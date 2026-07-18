# CLI dispatcher (FR-X-2 json output, FR-X-3 exit codes).

with_dir <- function(dir, code) {
  old <- setwd(dir)
  on.exit(setwd(old), add = TRUE)
  force(code)
}

test_that("main: init then scan exit 0; --format json emits machine output", {
  root <- local_example_project()
  with_dir(root, {
    expect_identical(main(c("scan")), 0L)
    out <- capture.output(code <- main(c("scan", "--format", "json")))
    expect_identical(code, 0L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"))
    expect_identical(parsed$summary$total, 5L)
    expect_identical(parsed$command, "scan")
    expect_identical(parsed$status, "ok")
  })

  fresh <- tempfile("cli-init-")
  dir.create(fresh)
  with_dir(fresh, expect_identical(main(c("init")), 0L))
  expect_true(file.exists(file.path(fresh, "validation", "avior.yml")))
})

test_that("main: execution errors return 2 (FR-X-3)", {
  empty <- tempfile("cli-empty-")
  dir.create(empty)
  with_dir(empty, {
    expect_identical(suppressMessages(main(c("scan"))), 2L)          # no config
    expect_identical(suppressMessages(main(c("frobnicate"))), 2L)    # unknown cmd
    expect_identical(suppressMessages(main(character(0))), 2L)       # no command
  })
})

test_that("json error envelope is machine readable", {
  empty <- tempfile("cli-empty-")
  dir.create(empty)
  with_dir(empty, {
    out <- capture.output(code <- suppressMessages(main(c("scan", "--format", "json"))))
    expect_identical(code, 2L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"))
    expect_identical(parsed$status, "error")
    expect_true(nzchar(parsed$message))
  })
})

# machine-interface stability (PR #18 review)

json_of <- function(argv) {
  out <- capture.output(suppressWarnings(suppressMessages(main(argv))))
  jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
}

package_version_from_description <- function() {
  description <- system.file("DESCRIPTION", package = "avior", mustWork = TRUE)
  as.character(read.dcf(description)[1, "Version"])
}

test_that("--help and --version are successful text and JSON commands", {
  help_text <- capture.output(help_code <- main("--help"))
  expect_identical(help_code, 0L)
  expect_true(all(c("init", "scan", "assess", "review", "check") %in%
                  unlist(strsplit(paste(help_text, collapse = " "), " "))))

  version_text <- capture.output(version_code <- main("--version"))
  expect_identical(version_code, 0L)
  expect_match(paste(version_text, collapse = ""),
               package_version_from_description(),
               fixed = TRUE)

  help_json <- json_of(c("--help", "--format", "json"))
  expect_identical(help_json$status, "ok")
  expect_true(is.list(help_json$commands))
  expect_setequal(unlist(help_json$commands),
                  c("init", "scan", "assess", "review", "check"))
  expect_identical(json_of(c("--version", "--format", "json"))$status, "ok")
})

test_that("command metadata helpers are authoritative for command errors", {
  commands <- c("init", "scan", "assess", "review", "check")
  hint <- "init|scan|assess|review|check"

  expect_identical(avior_command_names(), commands)
  expect_identical(avior_command_hint(), hint)
  expect_identical(avior_version(), package_version_from_description())

  no_command <- capture.output(no_command_code <- main(character(0)), type = "message")
  expect_identical(no_command_code, 2L)
  expect_match(paste(no_command, collapse = " "), hint, fixed = TRUE)

  unknown <- capture.output(unknown_code <- main("frobnicate"), type = "message")
  expect_identical(unknown_code, 2L)
  expect_match(paste(unknown, collapse = " "), hint, fixed = TRUE)
})

test_that("metadata commands reject extra text and JSON arguments (exit 2)", {
  for (command in c("--help", "--version")) {
    capture.output(
      text_code <- suppressMessages(main(c(command, "junk")))
    )
    expect_identical(text_code, 2L)

    json_output <- capture.output(
      json_code <- suppressMessages(main(c(command, "junk", "--format", "json")))
    )
    expect_identical(json_code, 2L)
    expect_identical(
      jsonlite::fromJSON(paste(json_output, collapse = "\n"))$status,
      "error"
    )
  }
})

test_that("JSON collection fields are always arrays (0/1/2 elements)", {
  # 0 skipped: a clean scan must still emit skipped_files as []
  r0 <- local_example_project()
  with_dir(r0, {
    p <- json_of(c("scan", "--format", "json"))
    expect_true(is.list(p$skipped_files) && length(p$skipped_files) == 0)
  })
  # exactly 1 skipped file — the case that most easily breaks a consumer
  r1 <- local_example_project()
  writeLines("minqa::foo(", file.path(r1, "analysis", "b1.R"))
  with_dir(r1, {
    p <- json_of(c("scan", "--format", "json"))
    expect_true(is.list(p$skipped_files) && length(p$skipped_files) == 1)
  })
  # 2 skipped files
  r2 <- local_example_project()
  writeLines("minqa::foo(", file.path(r2, "analysis", "b1.R"))
  writeLines("x::y(", file.path(r2, "analysis", "b2.R"))
  with_dir(r2, {
    p <- json_of(c("scan", "--format", "json"))
    expect_true(is.list(p$skipped_files) && length(p$skipped_files) == 2)
  })
  # init: created/skipped stay arrays across a first and idempotent second run
  fresh <- tempfile("cli-arr-"); dir.create(fresh)
  with_dir(fresh, {
    p1 <- json_of(c("init", "--format", "json"))
    expect_true(is.list(p1$created) && length(p1$created) >= 1)
    expect_true(is.list(p1$skipped) && length(p1$skipped) == 0)
    p2 <- json_of(c("init", "--format", "json"))
    expect_true(is.list(p2$created) && length(p2$created) == 0)
    expect_true(is.list(p2$skipped) && length(p2$skipped) >= 1)
  })
})

test_that("init --ci generates a workflow; bad values are execution errors (#25)", {
  fresh <- tempfile("cli-ci-"); dir.create(fresh)
  with_dir(fresh, {
    out <- capture.output(code <- main(c("init", "--ci", "github",
                                         "--format", "json")))
    expect_identical(code, 0L)
    parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                                 simplifyVector = FALSE)
    expect_identical(parsed$status, "ok")
    expect_true(any(grepl("workflows", unlist(parsed$created))))
    expect_true(file.exists(file.path(".github", "workflows", "avior.yml")))

    bad <- list(
      c("init", "--ci"),                           # missing value
      c("init", "--ci", "circleci"),               # unsupported provider
      c("init", "--ci", "github", "--ci", "gitlab") # duplicate
    )
    for (argv in bad) {
      expect_identical(suppressMessages(main(argv)), 2L)
      out <- capture.output(
        code <- suppressMessages(main(c(argv, "--format", "json"))))
      expect_identical(code, 2L)
      expect_identical(
        jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "error")
    }
  })
})

test_that("assess --refresh-na maps to refresh_na and gates cache retries (#23)", {
  metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
               "downloads_1yr", "covr_coverage", "last_30_bugs_status")
  vals <- stats::setNames(as.list(rep(0.9, length(metrics))), metrics)
  vals$downloads_1yr <- NULL   # network metric that stays NA -> refreshable
  pkgs <- c("jsonlite", "lme4", "mvtnorm", "survival")
  counter <- new.env(); counter$n <- 0L
  eng <- avior:::mock_engine(
    stats::setNames(rep(list(vals), length(pkgs)), pkgs),
    id = "mock-cli",
    network_metrics = "downloads_1yr",
    execution_metrics = "covr_coverage",
    counter = counter
  )
  avior:::engine_register(eng)
  on.exit(rm("mock-cli", envir = avior:::engines_env), add = TRUE)

  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("engine: riskmetric", "engine: mock-cli", readLines(f)), f)

  with_dir(root, {
    expect_identical(main(c("scan")), 0L)
    expect_identical(main(c("assess", "--deep")), 0L)
    n1 <- counter$n
    expect_identical(n1, 4L)

    # default (refresh_na = TRUE): every package retries its network NA
    expect_identical(main(c("assess", "--deep")), 0L)
    expect_identical(counter$n, n1 + 4L)

    # --refresh-na false: valid cache entries are full hits, zero engine calls
    expect_identical(main(c("assess", "--deep", "--refresh-na", "false")), 0L)
    expect_identical(counter$n, n1 + 4L)
    out <- capture.output(
      code <- main(c("assess", "--deep", "--refresh-na", "false",
                     "--format", "json")))
    expect_identical(code, 0L)
    expect_identical(jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "ok")
    expect_identical(counter$n, n1 + 4L)

    # --refresh-na true: explicit form of the default
    expect_identical(main(c("assess", "--deep", "--refresh-na", "true")), 0L)
    expect_identical(counter$n, n1 + 8L)
  })
})

test_that("assess --refresh-na rejects duplicates and invalid values (exit 2)", {
  root <- local_example_project()
  with_dir(root, {
    bad <- list(
      c("assess", "--refresh-na"),                            # missing value
      c("assess", "--refresh-na", "maybe"),                   # invalid value
      c("assess", "--refresh-na", "true", "--refresh-na", "false")  # duplicate
    )
    for (argv in bad) {
      expect_identical(suppressMessages(main(argv)), 2L)
      out <- capture.output(
        code <- suppressMessages(main(c(argv, "--format", "json"))))
      expect_identical(code, 2L)
      expect_identical(
        jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "error")
    }
  })
})

test_that("unknown/unconsumed command arguments are rejected (exit 2)", {
  root <- local_example_project()
  with_dir(root, {
    expect_identical(suppressMessages(main(c("scan", "--bogus"))), 2L)
    expect_identical(suppressMessages(main(c("scan", "--deep"))), 2L)   # assess-only flag
    expect_identical(suppressMessages(main(c("scan", "extra"))), 2L)    # stray positional
    # the rejection survives --format stripping
    out <- capture.output(
      code <- suppressMessages(main(c("scan", "--bogus", "--format", "json"))))
    expect_identical(code, 2L)
    expect_identical(jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "error")
  })
  fresh <- tempfile("cli-badargs-"); dir.create(fresh)
  with_dir(fresh, expect_identical(suppressMessages(main(c("init", "--bogus"))), 2L))
})
