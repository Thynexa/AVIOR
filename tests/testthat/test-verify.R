# avior verify — standalone bundle integrity verification (FR-VERIFY-1..3).

# A minimal well-formed bundle built from scratch: verify must not depend
# on any project context (FR-VERIFY-2), so neither do its tests.
local_mini_bundle <- function(env = parent.frame()) {
  dir <- file.path(tempfile("bundle-fx-"), "bundle-20260101T000000Z")
  dir.create(file.path(dir, "snapshot"), recursive = TRUE)
  writeLines("avior: 1", file.path(dir, "BUNDLE.yml"))
  writeLines('{"x": 1}', file.path(dir, "environment.json"))
  writeLines("policy: here", file.path(dir, "snapshot", "avior.yml"))
  rels <- c("BUNDLE.yml", "environment.json", "snapshot/avior.yml")
  manifest <- vapply(rels, function(p) {
    paste0(avior:::sha256_file(file.path(dir, p)), "  ", p)
  }, character(1))
  # write_lines_lf, not writeLines: the strict parser requires LF-only
  # manifests, and writeLines emits CRLF on Windows
  avior:::write_lines_lf(manifest, file.path(dir, "MANIFEST.sha256"))
  withr_defer_dir(dirname(dir), env)
  dir
}

finding_types <- function(res) {
  vapply(res$findings, function(f) f$type, character(1))
}

test_that("a clean bundle directory verifies with a stable anchor", {
  dir <- local_mini_bundle()
  res <- avior_verify(dir)
  expect_identical(res$status, "pass")
  expect_identical(res$source, "directory")
  expect_identical(res$files_checked, 3L)
  expect_identical(res$anchor,
                   avior:::sha256_file(file.path(dir, "MANIFEST.sha256")))
  expect_length(res$findings, 0L)
})

test_that("the committed sample bundle verifies as directory and zip", {
  repo <- repo_example_path()
  skip_if(is.na(repo), "repo example not available (running from built package)")
  sample <- file.path(repo, "validation", "evidence",
                      "bundle-20260708T120000Z")
  res <- avior_verify(sample)
  expect_identical(res$status, "pass")
  expect_identical(res$files_checked, 13L)

  # zip parity: pack the same bundle as a transport zip, verify that
  z <- tempfile(fileext = ".zip")
  on.exit(unlink(z), add = TRUE)
  files <- list.files(sample, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  avior:::zip_write(z, dirname(sample),
                    files = file.path(basename(sample), files))
  zres <- avior_verify(z)
  expect_identical(zres$status, "pass")
  expect_identical(zres$source, "zip")
  expect_identical(zres$anchor, res$anchor)
})

test_that("tampering with one byte names the exact file (exit 1)", {
  dir <- local_mini_bundle()
  target <- file.path(dir, "snapshot", "avior.yml")
  raw <- readBin(target, "raw", file.size(target))
  raw[1] <- as.raw(bitwXor(as.integer(raw[1]), 1L))
  writeBin(raw, target)

  res <- avior_verify(dir)
  expect_identical(res$status, "fail")
  expect_null(res$anchor)
  mods <- Filter(function(f) f$type == "modified", res$findings)
  expect_length(mods, 1L)
  expect_identical(mods[[1]]$path, "snapshot/avior.yml")
  expect_match(mods[[1]]$expected, "^[0-9a-f]{64}$")
  expect_match(mods[[1]]$actual, "^[0-9a-f]{64}$")
  expect_false(identical(mods[[1]]$expected, mods[[1]]$actual))
})

test_that("missing and unexpected files are typed findings", {
  dir <- local_mini_bundle()
  unlink(file.path(dir, "environment.json"))
  writeLines("stowaway", file.path(dir, ".hidden-extra"))

  res <- avior_verify(dir)
  expect_identical(res$status, "fail")
  types <- finding_types(res)
  expect_true("missing" %in% types)
  expect_true("unexpected" %in% types)
  paths <- vapply(res$findings, function(f) f$path, character(1))
  expect_true("environment.json" %in% paths)
  expect_true(".hidden-extra" %in% paths)
})

test_that("manifest mutations are typed malformed/duplicate findings", {
  cases <- list(
    list(mut = function(l) sub("  ", " ", l[1]),        type = "malformed"),  # one space
    list(mut = function(l) sub("  ", "   ", l[1]),      type = "malformed"),  # three spaces
    list(mut = function(l) sub("  ", "  *", l[1]),      type = "malformed"),  # binary marker
    list(mut = function(l) c(paste0(toupper(substr(l[1], 1, 64)),
                                    substring(l[1], 65)), l[-1]),
         type = "malformed"),                                                 # uppercase hex
    list(mut = function(l) c(substring(l[1], 2), l[-1]), type = "malformed"), # 63-char hash
    list(mut = function(l) c(l, ""), type = "malformed", skip_ok = TRUE),     # blank interior line
    list(mut = function(l) c(l, l[1]), type = "duplicate"),                   # duplicate path
    list(mut = function(l) rev(l), type = "malformed"),                       # unsorted
    list(mut = function(l) c(l, paste0(strrep("a", 64), "  ../escape")),
         type = "malformed"),                                                 # traversal
    list(mut = function(l) c(l, paste0(strrep("a", 64), "  /abs/path")),
         type = "malformed"),                                                 # absolute
    list(mut = function(l) c(l, paste0(strrep("a", 64), "  C:\\win")),
         type = "malformed"),                                                 # drive letter
    list(mut = function(l) c(l, paste0(strrep("a", 64), "  MANIFEST.sha256")),
         type = "malformed")                                                  # self-reference
  )
  for (i in seq_along(cases)) {
    dir <- local_mini_bundle()
    mpath <- file.path(dir, "MANIFEST.sha256")
    lines <- readLines(mpath)
    avior:::write_lines_lf(cases[[i]]$mut(lines), mpath)
    res <- avior_verify(dir)
    expect_identical(res$status, "fail", label = paste("case", i, "status"))
    expect_true(cases[[i]]$type %in% finding_types(res),
                label = paste("case", i, "type", cases[[i]]$type))
    unlink(dir, recursive = TRUE)
  }
})

test_that("a blank interior line does not hide later corruption", {
  dir <- local_mini_bundle()
  mpath <- file.path(dir, "MANIFEST.sha256")
  lines <- readLines(mpath)
  avior:::write_lines_lf(c(lines[1], "", lines[-1]), mpath)
  res <- avior_verify(dir)
  expect_identical(res$status, "fail")
  malformed <- Filter(function(f) f$type == "malformed", res$findings)
  expect_true(any(vapply(malformed, function(f) identical(f$line, 2L),
                         logical(1))))
})

test_that("CRLF corruption is a malformed finding naming the line", {
  dir <- local_mini_bundle()
  mpath <- file.path(dir, "MANIFEST.sha256")
  txt <- readChar(mpath, file.size(mpath), useBytes = TRUE)
  con <- file(mpath, open = "wb")
  writeBin(charToRaw(gsub("\n", "\r\n", txt, fixed = TRUE)), con)
  close(con)
  res <- avior_verify(dir)
  expect_identical(res$status, "fail")
  # every line is malformed; the now-unlisted files surface as unexpected
  expect_true("malformed" %in% finding_types(res))
  expect_match(res$findings[[1]]$message, "CRLF")
})

test_that("findings order is deterministic: category then path", {
  dir <- local_mini_bundle()
  unlink(file.path(dir, "environment.json"))              # missing
  writeLines("x", file.path(dir, "zzz-extra"))            # unexpected
  writeLines("y", file.path(dir, "aaa-extra"))            # unexpected
  mpath <- file.path(dir, "MANIFEST.sha256")
  avior:::write_lines_lf(c("bogus line", readLines(mpath)), mpath)  # malformed
  res <- avior_verify(dir)
  types <- finding_types(res)
  # category order is fixed: malformed < missing < unexpected here
  expect_identical(unique(types), c("malformed", "missing", "unexpected"))
  unexpected <- vapply(Filter(function(f) f$type == "unexpected",
                              res$findings), function(f) f$path, character(1))
  expect_identical(unexpected, avior:::sort_c(unexpected))
})

test_that("hostile zips are refused before extraction (exit 2)", {
  payload <- charToRaw("owned")
  hostile <- list(
    "../escape.txt" = payload,
    "/abs.txt" = payload,
    "C:\\win.txt" = payload,
    "a/../b.txt" = payload,
    # DIRECTORY entries must be validated too: a trailing `/` used to
    # bypass the path-safety check entirely
    "../escape/" = payload,
    "C:\\escape\\" = payload,
    "a/../" = payload
  )
  for (name in names(hostile)) {
    z <- tempfile(fileext = ".zip")
    avior:::zip_write_entries(z, stats::setNames(list(payload), name))
    err <- tryCatch(avior_verify(z), avior_error = function(e) e)
    expect_s3_class(err, "avior_error")
    expect_match(conditionMessage(err), "unsafe zip entry", fixed = TRUE,
                 label = name)
    unlink(z)
  }

  # duplicate entries are ambiguous -> refuse
  z <- tempfile(fileext = ".zip")
  dup_entries <- list(payload, payload)
  names(dup_entries) <- rep("MANIFEST.sha256", 2)
  avior:::zip_write_entries(z, dup_entries)
  err <- tryCatch(avior_verify(z), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "more than once")

  # entries that alias each other after ASCII case-folding extract to the
  # SAME file on default macOS/Windows filesystems: verification of such
  # an archive would depend on the host, so it is refused everywhere.
  # This archive would otherwise VERIFY on a case-insensitive filesystem:
  # `A` and `a` share content and the manifest lists both.
  content <- charToRaw("same-bytes\n")
  sha <- digest::digest(content, algo = "sha256", serialize = FALSE)
  manifest <- charToRaw(paste0(sha, "  A\n", sha, "  a\n"))
  z <- tempfile(fileext = ".zip")
  avior:::zip_write_entries(z, list(
    "A" = content, "MANIFEST.sha256" = manifest, "a" = content))
  err <- tryCatch(avior_verify(z), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "case-folded")

  # a directory row aliasing a file after case-folding is refused too
  z <- tempfile(fileext = ".zip")
  avior:::zip_write_entries(z, list(
    "MANIFEST.sha256" = manifest, "x" = content, "X/" = raw(0)))
  err <- tryCatch(avior_verify(z), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "more than once")

  # non-ASCII entry names are refused outright: NFC ("caf\u00e9") and NFD
  # ("cafe\u0301") are distinct entries on Linux but alias ONE path on
  # default macOS filesystems, which tolower() cannot detect; transport
  # zips only ever carry ASCII bundle paths
  for (name in c("caf\u00e9.txt", "cafe\u0301.txt")) {
    z <- tempfile(fileext = ".zip")
    entries <- list(content)
    names(entries) <- name
    avior:::zip_write_entries(z, entries)
    err <- tryCatch(avior_verify(z), avior_error = function(e) e)
    expect_s3_class(err, "avior_error")
    expect_match(conditionMessage(err), "non-ASCII")
    unlink(z)
  }

  # no file escaped into the extraction parent
  leaks <- list.files(tempdir(), pattern = "escape|owned", recursive = TRUE)
  expect_length(leaks, 0L)
})

test_that("non-bundle inputs are execution errors (exit 2)", {
  err <- tryCatch(avior_verify(tempfile("nope-")),
                  avior_error = function(e) e)
  expect_match(conditionMessage(err), "bundle not found")

  empty <- tempfile("empty-"); dir.create(empty)
  err <- tryCatch(avior_verify(empty), avior_error = function(e) e)
  expect_match(conditionMessage(err), "not an avior bundle")

  txt <- tempfile(fileext = ".zip"); writeLines("not a zip", txt)
  err <- tryCatch(avior_verify(txt), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")

  # a zip with no manifest anywhere -> unsupported layout
  z <- tempfile(fileext = ".zip")
  avior:::zip_write_entries(z, list("data.txt" = charToRaw("x")))
  err <- tryCatch(avior_verify(z), avior_error = function(e) e)
  expect_match(conditionMessage(err), "unsupported archive layout|not an avior bundle")
})

test_that("verify runs without any project context (FR-VERIFY-2)", {
  dir <- local_mini_bundle()
  bare <- tempfile("bare-cwd-"); dir.create(bare)
  old <- setwd(bare); on.exit(setwd(old), add = TRUE)
  expect_identical(avior_verify(dir)$status, "pass")
})

test_that("CLI: verify exit codes, JSON envelope, and arg validation", {
  dir <- local_mini_bundle()
  expect_identical(main(c("verify", dir)), 0L)

  out <- capture.output(code <- main(c("verify", dir, "--format", "json")))
  expect_identical(code, 0L)
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                               simplifyVector = FALSE)
  expect_identical(parsed$command, "verify")
  expect_identical(parsed$status, "pass")
  expect_identical(parsed$files_checked, 3L)
  expect_match(parsed$anchor, "^[0-9a-f]{64}$")
  expect_true(is.list(parsed$findings) && length(parsed$findings) == 0)

  # tamper -> exit 1 with typed findings in JSON
  writeLines("tampered", file.path(dir, "BUNDLE.yml"))
  expect_identical(suppressMessages(main(c("verify", dir))), 1L)
  out <- capture.output(
    code <- suppressMessages(main(c("verify", dir, "--format", "json"))))
  expect_identical(code, 1L)
  parsed <- jsonlite::fromJSON(paste(out, collapse = "\n"),
                               simplifyVector = FALSE)
  expect_identical(parsed$status, "fail")
  expect_identical(parsed$findings[[1]]$type, "modified")

  # arg validation
  expect_identical(suppressMessages(main(c("verify"))), 2L)
  expect_identical(suppressMessages(main(c("verify", dir, "extra"))), 2L)
})
