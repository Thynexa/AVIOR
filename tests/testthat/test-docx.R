# DOCX structural validation (issue #33): the hand-rolled OOXML must open
# in Word — parts present, well-formed-ish XML, headings/tables/page breaks
# preserved, deterministic bytes.

docx_model <- function() mini_model()   # from helper-report.R

render_docx_tmp <- function(model, env = parent.frame()) {
  out <- tempfile("docx-"); dir.create(out)
  withr_defer_dir(out, env)
  avior:::render_report(model, list(formats = "docx", language = "en"), out)
  file.path(out, "report.docx")
}

read_part <- function(docx, part) {
  tmp <- tempfile("docx-part-")
  utils::unzip(docx, exdir = tmp, unzip = "internal")
  p <- file.path(tmp, part)
  txt <- readChar(p, file.size(p), useBytes = TRUE)
  unlink(tmp, recursive = TRUE)
  txt
}

test_that("report.docx contains every required OOXML part", {
  docx <- render_docx_tmp(docx_model())
  parts <- utils::unzip(docx, list = TRUE)$Name
  for (p in c("[Content_Types].xml", "_rels/.rels", "word/document.xml",
              "word/styles.xml", "word/_rels/document.xml.rels")) {
    expect_true(p %in% parts, label = p)
  }
})

test_that("document.xml preserves headings, tables, and page breaks", {
  docx <- render_docx_tmp(docx_model())
  doc <- read_part(docx, "word/document.xml")

  count <- function(pat) {
    length(gregexpr(pat, doc, fixed = TRUE)[[1]])
  }
  # heading structure: 1 title + 7 sections + 2 appendices
  expect_identical(count("w:val=\"Heading1\""), 1L)
  expect_identical(count("w:val=\"Heading2\""), 9L)
  # tables: cover kv, sec2 disclaimer, sec3, sec4, sec5, sec6, sec7 kv,
  # appendix A
  expect_identical(count("<w:tbl>"), 8L)
  expect_identical(count("<w:tbl>"), count("</w:tbl>"))
  # explicit page breaks before each appendix
  expect_identical(count("<w:br w:type=\"page\"/>"), 2L)
  # crude well-formedness: these tags are never self-closed, so every
  # opener must have a closer
  for (tag in c("w:tbl", "w:tr", "w:tc", "w:r", "w:t")) {
    opened <- length(gregexpr(paste0("<", tag, "[ >]"), doc)[[1]])
    closed <- count(paste0("</", tag, ">"))
    expect_identical(opened, closed, label = tag)
  }
  # section titles made it into the body text
  expect_match(doc, "2. Scope and boundary statement", fixed = TRUE)
  expect_match(doc, "Appendix B - Integrity", fixed = TRUE)
})

test_that("content types and relationships wire the package together", {
  docx <- render_docx_tmp(docx_model())
  ct <- read_part(docx, "[Content_Types].xml")
  expect_match(ct, "wordprocessingml.document.main", fixed = TRUE)
  expect_match(ct, "wordprocessingml.styles", fixed = TRUE)
  rels <- read_part(docx, "_rels/.rels")
  expect_match(rels, "Target=\"word/document.xml\"", fixed = TRUE)
  drels <- read_part(docx, "word/_rels/document.xml.rels")
  expect_match(drels, "Target=\"styles.xml\"", fixed = TRUE)
  styles <- read_part(docx, "word/styles.xml")
  expect_match(styles, "w:styleId=\"Heading1\"", fixed = TRUE)
  expect_match(styles, "w:styleId=\"Heading2\"", fixed = TRUE)
})

test_that("report.docx bytes are deterministic under SOURCE_DATE_EPOCH", {
  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752000000")
  on.exit(if (is.na(old)) Sys.unsetenv("SOURCE_DATE_EPOCH") else
            Sys.setenv(SOURCE_DATE_EPOCH = old), add = TRUE)
  m <- docx_model()
  d1 <- render_docx_tmp(m)
  d2 <- render_docx_tmp(m)
  expect_identical(readBin(d1, "raw", file.size(d1)),
                   readBin(d2, "raw", file.size(d2)))
})
