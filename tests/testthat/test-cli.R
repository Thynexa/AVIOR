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
