test_that("sha256_file matches system sha256sum output", {
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  avior:::write_lines_lf(c("hello", "world"), p)
  expected <- if (nzchar(Sys.which("sha256sum"))) {
    strsplit(system2("sha256sum", p, stdout = TRUE), " ")[[1]][1]
  } else {
    skip("sha256sum not available")
  }
  expect_identical(avior:::sha256_file(p), expected)
})

test_that("avior_abort signals a classed condition", {
  expect_error(avior:::avior_abort("boom"), class = "avior_error")
  expect_error(avior:::avior_abort("boom", class = "avior_config_error"),
               class = "avior_config_error")
  # subclass still carries the base class
  cond <- tryCatch(avior:::avior_abort("x", class = "avior_config_error"),
                   condition = function(c) c)
  expect_true(inherits(cond, "avior_error"))
})

test_that("finding() builds a structured check finding", {
  f <- avior:::finding("lme4", "missing_decision", "no decision record",
                       fix = "run: avior review")
  expect_identical(f$package, "lme4")
  expect_identical(f$type, "missing_decision")
  expect_identical(f$fix, "run: avior review")
})
