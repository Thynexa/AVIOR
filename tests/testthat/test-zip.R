# Deterministic stored-zip writer (transport artifacts, FR-BUNDLE-8).

local_zip_env <- function(epoch = "1752000000", env = parent.frame()) {
  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = epoch)
  do.call(on.exit, list(bquote(
    if (is.na(.(old))) Sys.unsetenv("SOURCE_DATE_EPOCH") else
      Sys.setenv(SOURCE_DATE_EPOCH = .(old))
  ), add = TRUE), envir = env)
}

make_tree <- function() {
  root <- tempfile("ziptree-")
  dir.create(file.path(root, "sub"), recursive = TRUE)
  writeLines("alpha", file.path(root, "a.txt"))
  writeLines(c("b content", "line 2"), file.path(root, "sub", "b.txt"))
  writeLines("hidden", file.path(root, ".dotfile"))
  root
}

test_that("zip_write is byte-deterministic under SOURCE_DATE_EPOCH", {
  local_zip_env()
  root <- make_tree()
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  z1 <- tempfile(fileext = ".zip"); avior:::zip_write(z1, root)
  z2 <- tempfile(fileext = ".zip"); avior:::zip_write(z2, root)
  expect_identical(readBin(z1, "raw", file.size(z1)),
                   readBin(z2, "raw", file.size(z2)))
})

test_that("utils::unzip round-trips zip_write output byte-for-byte", {
  local_zip_env()
  root <- make_tree()
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  z <- tempfile(fileext = ".zip")
  avior:::zip_write(z, root)

  listing <- utils::unzip(z, list = TRUE)
  # C-locale order, dotfiles included, no directory entries
  expect_identical(listing$Name, c(".dotfile", "a.txt", "sub/b.txt"))

  out <- tempfile("unz-")
  utils::unzip(z, exdir = out, unzip = "internal")
  for (rel in listing$Name) {
    a <- file.path(root, rel); b <- file.path(out, rel)
    expect_identical(readBin(a, "raw", file.size(a)),
                     readBin(b, "raw", file.size(b)),
                     label = paste("byte-identical after round trip:", rel))
  }
})

test_that("a pre-1980 epoch clamps to the DOS timestamp floor", {
  local_zip_env(epoch = "0")
  root <- make_tree()
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  z <- tempfile(fileext = ".zip")
  expect_no_error(avior:::zip_write(z, root))
  expect_identical(utils::unzip(z, list = TRUE)$Name,
                   c(".dotfile", "a.txt", "sub/b.txt"))
})

test_that("crc32 conversion survives values above 2^31", {
  # regression guard for the strtoi()/bitwAnd() overflow class of bug:
  # find a payload whose crc32 has the top bit set and round-trip it
  local_zip_env()
  root <- tempfile("crc-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  found <- FALSE
  for (i in 1:64) {
    writeLines(paste0("payload-", i), file.path(root, "x.txt"))
    crc <- avior:::zip_crc32(readBin(file.path(root, "x.txt"), "raw",
                                     file.size(file.path(root, "x.txt"))))
    if (crc >= 2^31) { found <- TRUE; break }
  }
  expect_true(found)
  z <- tempfile(fileext = ".zip")
  avior:::zip_write(z, root)
  out <- tempfile("crc-out-")
  expect_no_error(utils::unzip(z, exdir = out, unzip = "internal"))
  expect_identical(readLines(file.path(out, "x.txt")),
                   readLines(file.path(root, "x.txt")))
})

test_that("zip_write on a missing file is an execution error", {
  root <- tempfile("gone-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  err <- tryCatch(avior:::zip_write(tempfile(fileext = ".zip"), root,
                                    files = "nope.txt"),
                  avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
})
