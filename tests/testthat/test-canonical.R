# FR-X-8 canonical serialization. These byte-level rules are the foundation
# of every "repeated runs are byte-identical" AC (NFR-1), so they are tested
# exhaustively here and every writer below must go through them.

# --- number formatting ------------------------------------------------------

test_that("avior_format_num: decimal notation, <=4 fractional digits, >=1 kept", {
  f <- avior:::avior_format_num
  expect_identical(f(1), "1.0")
  expect_identical(f(0), "0.0")
  expect_identical(f(0.5), "0.5")
  expect_identical(f(0.61), "0.61")
  expect_identical(f(0.6100000000000001), "0.61")
  expect_identical(f(1e-04), "0.0001")
  expect_identical(f(0.00005), "0.0")        # rounds to 0 -> keep one digit
  expect_identical(f(0.12345), "0.1235")     # R round(): half-even on representable values
  expect_identical(f(123), "123.0")
  expect_identical(f(-0.25), "-0.25")
  expect_identical(f(NA_real_), NA_character_)
  expect_identical(f(c(1, 0.9)), c("1.0", "0.9"))
})

test_that("avior_format_num never emits scientific notation", {
  f <- avior:::avior_format_num
  expect_false(grepl("e", f(1e-04), fixed = TRUE))
  expect_false(grepl("e", f(123456), fixed = TRUE))
})

# --- timestamps -------------------------------------------------------------

test_that("avior_timestamp is UTC ISO-8601 seconds and honors SOURCE_DATE_EPOCH", {
  t <- as.POSIXct("2026-07-12 08:30:00", tz = "UTC")
  expect_identical(avior:::avior_timestamp(t), "2026-07-12T08:30:00Z")

  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752307200")  # 2025-07-12T08:00:00Z
  on.exit(if (is.na(old)) Sys.unsetenv("SOURCE_DATE_EPOCH") else Sys.setenv(SOURCE_DATE_EPOCH = old), add = TRUE)
  expect_identical(avior:::avior_timestamp(), "2025-07-12T08:00:00Z")
})

# --- raw line writer --------------------------------------------------------

test_that("write_lines_lf writes UTF-8, LF-only, trailing newline, no BOM", {
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  avior:::write_lines_lf(c("a", "b中文"), p)
  raw <- readBin(p, "raw", file.size(p))
  expect_false(as.raw(0x0D) %in% raw)                  # no CR anywhere
  expect_identical(raw[length(raw)], as.raw(0x0A))     # trailing newline
  expect_false(identical(raw[1:3], as.raw(c(0xEF, 0xBB, 0xBF))))  # no BOM
  expect_identical(readLines(p, encoding = "UTF-8"), c("a", "b中文"))
})

# --- YAML emitter -----------------------------------------------------------

test_that("write_yaml_canonical block style round-trips and is deterministic", {
  x <- list(
    avior = 1L,
    generated_by = "avior scan",
    lockfile = list(path = "renv.lock", sha256 = "abc123"),
    packages = list(
      list(name = "jsonlite", version = "1.8.8", in_scope = TRUE, weight = 1),
      list(name = "lme4", version = "1.1-35.1", in_scope = FALSE, note = NULL)
    ),
    summary = list(total = 2L, direct = 1L)
  )
  p1 <- tempfile(); p2 <- tempfile()
  on.exit(unlink(c(p1, p2)), add = TRUE)
  avior:::write_yaml_canonical(x, p1)
  avior:::write_yaml_canonical(x, p2)
  expect_identical(readBin(p1, "raw", file.size(p1)), readBin(p2, "raw", file.size(p2)))

  back <- avior:::read_yaml_file(p1)
  expect_identical(back$avior, 1L)
  expect_identical(back$lockfile$sha256, "abc123")
  expect_identical(back$packages[[1]]$name, "jsonlite")
  expect_identical(back$packages[[1]]$in_scope, TRUE)
  expect_identical(back$packages[[2]]$note, NULL)
  expect_identical(back$summary$total, 2L)
})

test_that("write_yaml_canonical emits true/false (not yes/no) and quotes as specified", {
  x <- list(ok = TRUE, no = FALSE, ver = "1.8.8", plain = "jsonlite",
            colon = "analysis/main.R:3", zh = "间接依赖",
            nul = NULL, num = 0.9)
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_yaml_canonical(x, p)
  txt <- readLines(p, encoding = "UTF-8")
  expect_true("ok: true" %in% txt)
  expect_true('"no": false' %in% txt)   # reserved word key -> quoted
  expect_true('ver: "1.8.8"' %in% txt)         # starts with digit -> quoted
  expect_true("plain: jsonlite" %in% txt)      # safe bare word -> unquoted
  expect_true('colon: "analysis/main.R:3"' %in% txt)
  expect_true("nul: null" %in% txt)
  expect_true("num: 0.9" %in% txt)             # numbers unquoted, canonical format
  back <- avior:::read_yaml_file(p)
  expect_identical(back$ver, "1.8.8")
  expect_identical(back$zh, "间接依赖")
})

test_that("write_yaml_canonical supports flow maps where the contract says so", {
  x <- list(
    engine = avior:::yaml_flow(list(id = "riskmetric", version = "0.2.4")),
    packages = list(
      avior:::yaml_flow(list(name = "jsonlite", version = "1.8.8", in_scope = TRUE))
    )
  )
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_yaml_canonical(x, p)
  txt <- readLines(p, encoding = "UTF-8")
  expect_true('engine: { id: riskmetric, version: "0.2.4" }' %in% txt)
  expect_true('  - { name: jsonlite, version: "1.8.8", in_scope: true }' %in% txt)
  back <- avior:::read_yaml_file(p)
  expect_identical(back$engine$id, "riskmetric")
  expect_identical(back$packages[[1]]$in_scope, TRUE)
})

test_that("write_yaml_canonical header comments are emitted before content", {
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_yaml_canonical(list(a = 1L), p, header = "generated by avior")
  txt <- readLines(p)
  expect_identical(txt[1], "# generated by avior")
  expect_identical(txt[2], "a: 1")
})

# --- JSON writer ------------------------------------------------------------

test_that("write_json_canonical: 2-space pretty, LF, trailing newline, deterministic", {
  x <- list(r_version = "4.3.2", lockfile = list(path = "renv.lock"),
            container = NULL, n = list(total = 5L), score = 0.61)
  p1 <- tempfile(); p2 <- tempfile()
  on.exit(unlink(c(p1, p2)), add = TRUE)
  avior:::write_json_canonical(x, p1)
  avior:::write_json_canonical(x, p2)
  expect_identical(readBin(p1, "raw", file.size(p1)), readBin(p2, "raw", file.size(p2)))
  raw <- readBin(p1, "raw", file.size(p1))
  expect_false(as.raw(0x0D) %in% raw)
  expect_identical(raw[length(raw)], as.raw(0x0A))
  back <- jsonlite::fromJSON(p1, simplifyVector = TRUE)
  expect_identical(back$r_version, "4.3.2")
  expect_true(is.null(back$container))
  expect_identical(back$n$total, 5L)
})

test_that("write_json_canonical never emits scientific notation (FR-X-8)", {
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  # jsonlite would render these as 1e+20 / 1.235e+06 / 1e-10 on its own
  avior:::write_json_canonical(
    list(big = 1e20, dur = 1234567.89, tiny = 1e-10, one = 1, score = 0.61,
         neg = -0.25, boundary = 0.12345, count = 5L, none = NA_real_), p)
  txt <- paste(readLines(p, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("[eE][+-]", txt))                    # no scientific anywhere
  expect_true(grepl('"big": 100000000000000000000.0', txt, fixed = TRUE))
  expect_true(grepl('"dur": 1234567.89', txt, fixed = TRUE))
  expect_true(grepl('"tiny": 0.0', txt, fixed = TRUE))
  expect_true(grepl('"one": 1.0', txt, fixed = TRUE))     # >=1 fractional digit kept
  expect_true(grepl('"score": 0.61', txt, fixed = TRUE))
  expect_true(grepl('"neg": -0.25', txt, fixed = TRUE))
  expect_true(grepl('"boundary": 0.1235', txt, fixed = TRUE))  # round-half-even
  expect_true(grepl('"count": 5', txt, fixed = TRUE))     # integer stays bare
  expect_true(grepl('"none": null', txt, fixed = TRUE))
  # the emitted numbers are real JSON numbers, not strings
  back <- jsonlite::fromJSON(p, simplifyVector = TRUE)
  expect_true(is.numeric(back$big))
  expect_identical(back$one, 1)
})

# --- CSV writer -------------------------------------------------------------

test_that("write_csv_canonical quotes only when needed (ASCII comma/quote/newline/non-ASCII)", {
  df <- data.frame(
    package = c("jsonlite", "lme4"),
    note = c("low risk, metadata only", "低风险"),  # ASCII comma / non-ASCII
    plain = c("ok", "x"),
    score = c(0.12, NA_real_),
    stringsAsFactors = FALSE
  )
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_csv_canonical(df, p)
  txt <- readLines(p, encoding = "UTF-8")
  expect_identical(txt[1], "package,note,plain,score")
  expect_identical(txt[2], 'jsonlite,"low risk, metadata only",ok,0.12')
  expect_identical(txt[3], 'lme4,"低风险",x,')      # NA -> empty field
  raw <- readBin(p, "raw", file.size(p))
  expect_false(as.raw(0x0D) %in% raw)
})

test_that("write_csv_canonical escapes embedded double quotes", {
  df <- data.frame(a = 'say "hi"', stringsAsFactors = FALSE)
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_csv_canonical(df, p)
  expect_identical(readLines(p)[2], '"say ""hi"""')
})

# --- C-locale ordering ------------------------------------------------------

test_that("sort_c / order_c use C-locale byte order (FR-X-7)", {
  x <- c("jsonlite", "Matrix", "survival", "MASS")
  expect_identical(avior:::sort_c(x), c("MASS", "Matrix", "jsonlite", "survival"))
  df <- data.frame(name = x, stringsAsFactors = FALSE)
  expect_identical(df$name[avior:::order_c(df$name)], c("MASS", "Matrix", "jsonlite", "survival"))
})
