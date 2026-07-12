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
