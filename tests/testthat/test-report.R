# English validation report + fail-closed Chinese placeholder (issue #33,
# FR-BUNDLE-3 narrative structure).

# mini_model() lives in helper-report.R (shared with test-docx.R): a
# hand-built all-ASCII model, so any non-ASCII byte in the English output
# would be template-owned.

en_strings <- function() avior:::report_locale_load("en")

test_that("locale tables: en is complete, zh is a schema-identical placeholder", {
  required <- avior:::report_strings_required()
  en_path <- system.file("report", "locales", "en.yml", package = "avior")
  zh_path <- system.file("report", "locales", "zh.yml", package = "avior")
  en <- avior:::read_yaml_file(en_path)
  zh <- avior:::read_yaml_file(zh_path)

  expect_identical(en$status, "complete")
  # exact key coverage in both directions: no missing, no orphan strings
  expect_setequal(names(en$strings), required)
  expect_identical(zh$status, "placeholder")
  expect_setequal(names(zh$strings), names(en$strings))

  # the English template itself is pure ASCII: nothing non-English can leak
  raw <- readBin(en_path, "raw", file.size(en_path))
  expect_true(all(raw <= as.raw(0x7F)))
})

test_that("selecting the zh placeholder fails closed with an actionable error", {
  err <- tryCatch(avior:::report_locale_load("zh"), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "not yet available")
  expect_match(conditionMessage(err), "report.language: en", fixed = TRUE)

  err <- tryCatch(avior:::report_locale_load("fr"), avior_error = function(e) e)
  expect_match(conditionMessage(err), "no locale table")

  err <- tryCatch(
    avior:::report_config_validate(list(formats = "pdf", language = "en")),
    avior_error = function(e) e)
  expect_match(conditionMessage(err), "unsupported report format")

  err <- tryCatch(
    avior:::report_config_validate(list(formats = character(0),
                                        language = "en")),
    avior_error = function(e) e)
  expect_match(conditionMessage(err), "at least one")
})

test_that("report_document follows the GAMP 5 narrative structure", {
  doc <- avior:::report_document(mini_model(), en_strings())
  headings <- vapply(Filter(function(b) identical(b$type, "heading"), doc),
                     function(b) b$text, character(1))
  expect_identical(headings[1], "AVIOR Validation Evidence Report")
  expect_identical(sub("\\..*$", "", headings[2:8]),
                   as.character(1:7))         # sections 1..7 in order
  expect_match(headings[9], "^Appendix A")
  expect_match(headings[10], "^Appendix B")

  types <- vapply(doc, function(b) b$type, character(1))
  expect_true("kv_table" %in% types)          # cover + environment tables
  expect_true("bullets" %in% types)           # layered exemption sourcing
  expect_identical(sum(types == "page_break"), 2L)  # before each appendix
  expect_false("banner" %in% types)           # clean bundle: no force banner

  forced <- avior:::report_document(mini_model(forced = TRUE), en_strings())
  ftypes <- vapply(forced, function(b) b$type, character(1))
  # the disclosure banner sits on the cover, before section 1
  expect_identical(ftypes[4], "banner")
  banner <- forced[[4]]$text
  expect_match(banner, "INTEGRITY CHECK FAILED")
  expect_match(banner, "2 open check finding")
  expect_match(banner, "failing_tests, stale_tests")
})

test_that("all-skipped rows read FAIL in the report and the trace (shared rule)", {
  m <- mini_model()
  skip_row <- list(file = "tests/test-alpha-skip.R", package = "alpha",
                   package_version = "1.0.0", tests = 1L, passed = 0L,
                   failed = 0L, skipped = 1L, duration_s = 0.1)
  m$tests$results <- c(m$tests$results, list(skip_row))

  # report section 6: the skipped row must not display as pass
  doc <- avior:::report_document(m, en_strings())
  tables <- Filter(function(b) identical(b$type, "table"), doc)
  sec6 <- Filter(function(b) any(grepl("Test file", b$header)), tables)[[1]]
  status_of <- function(file) {
    row <- Filter(function(r) identical(r[1], file), sec6$rows)[[1]]
    row[length(row)]
  }
  expect_identical(status_of("tests/test-alpha.R"), "pass")
  expect_identical(status_of("tests/test-alpha-skip.R"), "FAIL")

  # traceability: one green file must not mask the all-skipped sibling
  row <- avior:::trace_row(
    list(name = "alpha", version = "1.0.0", classification = "contributed",
         role = "direct", in_scope = TRUE),
    decisions = m$decisions, scores = m$scores, tests = m$tests)
  expect_identical(row$test_status, "fail")
})

test_that("the English HTML report is self-contained, complete, and ASCII-clean", {
  out <- tempfile("report-"); dir.create(out)
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  files <- avior:::render_report(
    mini_model(), list(formats = c("html", "docx"), language = "en"), out)
  expect_identical(files, c("report.html", "report.docx"))

  html_path <- file.path(out, "report.html")
  html <- readChar(html_path, file.size(html_path), useBytes = TRUE)

  # self-contained static file: no external asset, script, or image
  expect_false(grepl("http-equiv|<script|<img|@import|url\\(", html))
  expect_false(grepl("https?://", gsub("example.com", "", html)))
  # every section title present
  for (sec in c("1. Methodology", "2. Scope and boundary",
                "3. Scope and package classification",
                "4. Risk scoring", "5. Decision summary",
                "6. Targeted-test evidence",
                "7. Environment and reproducibility",
                "Appendix A", "Appendix B")) {
    expect_match(html, sec, fixed = TRUE, label = sec)
  }
  # facts reconcile with the model
  expect_match(html, "bundle-20260101T000000Z", fixed = TRUE)
  expect_match(html, "CRAN @ 2024-01-15", fixed = TRUE)
  expect_match(html, "version_managed", fixed = TRUE)
  expect_match(html, strrep("a", 64), fixed = TRUE)   # lockfile sha in sec 7
  # pure ASCII bytes: no Chinese (or any template non-ASCII) can leak
  raw <- readBin(html_path, "raw", file.size(html_path))
  expect_true(all(raw <= as.raw(0x7F)))
  # no template placeholders or TODOs survive rendering
  expect_false(grepl("\\{[a-z_]+\\}|TODO", html))
})

test_that("HTML output escapes hostile data", {
  m <- mini_model()
  m$decisions$alpha$use_statement <- "<script>alert('x')</script> & <b>"
  out <- tempfile("report-esc-"); dir.create(out)
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  avior:::render_report(m, list(formats = "html", language = "en"), out)
  html <- readChar(file.path(out, "report.html"),
                   file.size(file.path(out, "report.html")), useBytes = TRUE)
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_match(html, "&lt;script&gt;", fixed = TRUE)
  expect_match(html, "&amp; &lt;b&gt;", fixed = TRUE)
})

test_that("non-ASCII package metadata renders safely in both formats", {
  m <- mini_model()
  m$decisions$alpha$rationale <- "déjà vu — 用途"
  out <- tempfile("report-utf8-"); dir.create(out)
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  avior:::render_report(m, list(formats = c("html", "docx"),
                                language = "en"), out)
  html <- readChar(file.path(out, "report.html"),
                   file.size(file.path(out, "report.html")), useBytes = TRUE)
  Encoding(html) <- "UTF-8"
  expect_match(html, "déjà vu", fixed = TRUE)
  # docx: the run survives zip round-trip with intact UTF-8
  tmp <- tempfile("docx-utf8-")
  utils::unzip(file.path(out, "report.docx"), exdir = tmp, unzip = "internal")
  doc <- readChar(file.path(tmp, "word", "document.xml"),
                  file.size(file.path(tmp, "word", "document.xml")),
                  useBytes = TRUE)
  Encoding(doc) <- "UTF-8"
  expect_match(doc, "déjà vu", fixed = TRUE)
})

test_that("long text and empty optional fields render without breakage", {
  m <- mini_model()
  m$decisions$alpha$rationale <- strrep("long rationale text ", 200)
  m$decisions$alpha$use_statement <- NULL      # empty optional field
  m$scores$packages$alpha$note <- NULL
  out <- tempfile("report-long-"); dir.create(out)
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  files <- avior:::render_report(m, list(formats = c("html", "docx"),
                                         language = "en"), out)
  expect_length(files, 2L)
  html <- readChar(file.path(out, "report.html"),
                   file.size(file.path(out, "report.html")), useBytes = TRUE)
  expect_match(html, "long rationale text", fixed = TRUE)
})

test_that("bundle renders the reports and manifests them (issue #33 e2e)", {
  # reuse the bundle fixtures from test-bundle.R (files run alphabetically,
  # so redefine the tiny env helpers locally)
  testthat::local_mocked_bindings(
    capture_session = function() list(
      r_version = "4.3.2", platform = "x86_64-pc-linux-gnu",
      lc_collate = "C", blas = "b", lapack = "l",
      session_text = "mocked"), .package = "avior")
  old <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752000000")
  on.exit(if (is.na(old)) Sys.unsetenv("SOURCE_DATE_EPOCH") else
            Sys.setenv(SOURCE_DATE_EPOCH = old), add = TRUE)

  metrics <- c("has_vignettes", "has_news", "has_bug_reports_url",
               "downloads_1yr", "covr_coverage", "last_30_bugs_status")
  vals <- function(v) stats::setNames(as.list(rep(v, length(metrics))), metrics)
  eng <- avior:::mock_engine(
    list(jsonlite = vals(0.9), lme4 = vals(0.4),
         mvtnorm = vals(0.6), survival = vals(0.35)),
    execution_metrics = "covr_coverage",
    network_metrics = c("downloads_1yr", "last_30_bugs_status"))
  root <- local_example_project()
  unlink(file.path(root, "validation", c("inventory.yml", "scores.yml")))
  avior_scan(root)
  avior_assess(root, engine = eng, deep = TRUE)
  resnapshot_decisions(root)

  res <- avior_bundle(root)
  expect_identical(res$status, "ok")
  expect_identical(res$report_files, c("report.html", "report.docx"))
  bundle_dir <- file.path(root, res$path)
  expect_true(file.exists(file.path(bundle_dir, "report.html")))
  expect_true(file.exists(file.path(bundle_dir, "report.docx")))
  # the reports are covered by the manifest and the bundle still verifies
  manifest <- readLines(file.path(bundle_dir, "MANIFEST.sha256"))
  expect_true(any(grepl("  report.html$", manifest)))
  expect_true(any(grepl("  report.docx$", manifest)))
  expect_identical(avior_verify(bundle_dir)$status, "pass")

  # facts reconcile with BUNDLE.yml and the snapshots
  html <- readChar(file.path(bundle_dir, "report.html"),
                   file.size(file.path(bundle_dir, "report.html")),
                   useBytes = TRUE)
  expect_match(html, res$bundle_id, fixed = TRUE)
  inv <- avior:::read_yaml_file(file.path(bundle_dir, "snapshot",
                                          "inventory.yml"))
  expect_match(html, inv$lockfile$sha256, fixed = TRUE)

  # forced bundle: the failure is prominent in BOTH formats
  f <- file.path(root, "validation", "decisions", "survival.yml")
  writeLines(sub('version: "3.5-7"', 'version: "3.4-0"', readLines(f)), f)
  Sys.setenv(SOURCE_DATE_EPOCH = "1752000001")
  forced <- avior_bundle(root, force = TRUE)
  fdir <- file.path(root, forced$path)
  fhtml <- readChar(file.path(fdir, "report.html"),
                    file.size(file.path(fdir, "report.html")),
                    useBytes = TRUE)
  expect_match(fhtml, "INTEGRITY CHECK FAILED", fixed = TRUE)
  tmp <- tempfile("docx-forced-")
  utils::unzip(file.path(fdir, "report.docx"), exdir = tmp,
               unzip = "internal")
  doc <- readChar(file.path(tmp, "word", "document.xml"),
                  file.size(file.path(tmp, "word", "document.xml")),
                  useBytes = TRUE)
  expect_match(doc, "INTEGRITY CHECK FAILED", fixed = TRUE)
})

test_that("a zh-configured project fails closed before any write", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("language: en", "language: zh", readLines(f)), f)
  err <- tryCatch(avior_bundle(root), avior_error = function(e) e)
  expect_s3_class(err, "avior_error")
  expect_match(conditionMessage(err), "not yet available")
  # nothing was staged or written
  expect_length(list.files(file.path(root, "validation", "evidence"),
                           all.files = TRUE, no.. = TRUE), 0L)
})
