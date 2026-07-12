# Regression tests for the Phase 2 adversarial review findings.

test_that("F1: any unexpected error maps to exit 2, not 1 (FR-X-3)", {
  root <- tempfile("crash-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  # corrupt YAML -> parse error must surface as avior_config_error -> 2
  writeLines("policy: { unclosed", file.path(root, "validation", "avior.yml"))
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  expect_identical(suppressMessages(main("scan")), 2L)
  out <- capture.output(code <- suppressMessages(main(c("scan", "--format", "json"))))
  expect_identical(code, 2L)
  expect_identical(jsonlite::fromJSON(paste(out, collapse = "\n"))$status, "error")
})

test_that("F1b: raw (non-avior) crashes also exit 2 via the catch-all", {
  root <- tempfile("crash2-")
  # validation/avior.yml as a *directory*: file.exists() is TRUE, readChar
  # explodes with a plain R error -> catch-all must map it to 2
  dir.create(file.path(root, "validation", "avior.yml"), recursive = TRUE)
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  expect_identical(suppressWarnings(suppressMessages(main("scan"))), 2L)
})

test_that("F2: empty YAML sections keep defaults; scalar sections error", {
  root <- tempfile("cfg-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  f <- file.path(root, "validation", "avior.yml")
  writeLines(c("avior: 1",
               "scope:",              # empty section: all keys commented out
               "policy:",
               "  weights: { has_news: 1.0 }",
               "  rationale: ok"), f)
  cfg <- avior_config_load(root)
  expect_identical(cfg$scope$lockfile, "renv.lock")
  expect_identical(cfg$scope$intended_for_use, "auto")

  writeLines(c("avior: 1",
               "scope: renv.lock",    # scalar where a mapping is expected
               "policy:",
               "  weights: { has_news: 1.0 }",
               "  rationale: ok"), f)
  expect_error(avior_config_load(root), class = "avior_config_error")
})

test_that("F3+F15: explicit mode works with empty include; enum validated", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  txt <- readLines(f)
  txt <- sub("intended_for_use: auto.*", "intended_for_use: explicit", txt)
  txt <- sub("include: \\[survival\\].*", "include: []", txt)
  writeLines(txt, f)
  inv <- avior_scan(root)
  expect_identical(inv$summary$direct, 0L)
  expect_identical(inv$summary$in_scope_assessed, 0L)

  writeLines(sub("intended_for_use: explicit", "intended_for_use: explict",
                 readLines(f)), f)
  expect_error(avior_config_load(root), class = "avior_config_error")
})

test_that("F4: scope refs to packages absent from the lockfile warn (FR-SCAN-4)", {
  root <- local_example_project()
  f <- file.path(root, "validation", "avior.yml")
  writeLines(sub("include: \\[survival\\].*", "include: [survival, notinlock]",
                 readLines(f)), f)
  expect_warning(avior_scan(root), "notinlock")
})

test_that("F5: renamed validation dir works end-to-end; mismatch errors", {
  root <- local_example_project()
  file.rename(file.path(root, "validation"), file.path(root, "qa"))
  f <- file.path(root, "qa", "avior.yml")
  writeLines(sub("validation_dir: validation", "validation_dir: qa", readLines(f)), f)
  cfg <- avior_config_load(root)
  expect_identical(cfg$project$validation_dir, "qa")
  avior_scan(root)
  expect_true(file.exists(file.path(root, "qa", "inventory.yml")))

  # declared dir not matching the actual location is a config error
  writeLines(sub("validation_dir: qa", "validation_dir: elsewhere", readLines(f)), f)
  expect_error(avior_config_load(root), class = "avior_config_error")
})

test_that("F6: init output carries no CR bytes even from a CRLF template", {
  root <- tempfile("crlf-")
  dir.create(root)
  avior_init(root)
  raw <- readBin(file.path(root, "validation", "avior.yml"), "raw",
                 file.size(file.path(root, "validation", "avior.yml")))
  expect_false(as.raw(0x0D) %in% raw)
  # the template splitter itself strips CR
  expect_false(any(grepl("\r", avior:::init_config_template("x"), fixed = TRUE)))
})

test_that("F7: number formatting is exact above 7 significant digits", {
  f <- avior:::avior_format_num
  expect_identical(f(123456.7891), "123456.7891")
  expect_identical(f(-1234567.8912), "-1234567.8912")
  expect_identical(f(123456789.5), "123456789.5")
})

test_that("F8: JSON writer applies the 4-digit rule and avoids scientific", {
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_json_canonical(list(a = 1e-10, b = 0.123456), p)
  txt <- paste(readLines(p), collapse = "")
  expect_false(grepl("e-", txt, fixed = TRUE))
  expect_true(grepl('"b": 0.1235', txt, fixed = TRUE))
})

test_that("F9: YAML escapes newlines and quotes y/n forms", {
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_yaml_canonical(list(multi = "line1\nline2", flag = "n", why = "y"), p)
  back <- avior:::read_yaml_file(p)
  expect_identical(back$multi, "line1\nline2")
  expect_identical(back$flag, "n")   # not FALSE
  expect_identical(back$why, "y")    # not TRUE
})

test_that("F10: yaml_seq keeps single-element vectors as sequences", {
  p <- tempfile(); on.exit(unlink(p), add = TRUE)
  avior:::write_yaml_canonical(
    list(tests = avior:::yaml_seq("tests/test-lme4-fit.R"),
         none = avior:::yaml_seq(character(0))), p)
  txt <- readLines(p)
  expect_true(any(grepl("^tests: \\[", txt)))
  expect_true("none: []" %in% txt)
  back <- avior:::read_yaml_file(p)
  # the parser simplifies homogeneous sequences to vectors; what matters is
  # that the emitted form is a sequence, asserted on txt above
  expect_identical(back$tests, "tests/test-lme4-fit.R")
})

test_that("F11: named package= argument and help= form handled", {
  root <- tempfile("named-")
  dir.create(root)
  writeLines(c(
    'requireNamespace(quietly = TRUE, package = "pkgB")',
    "library(help = pkgG)"
  ), file.path(root, "named.R"))
  calls <- avior:::scan_direct_calls(root)
  expect_true("pkgB" %in% calls$package)
  expect_false("pkgG" %in% calls$package)
})

test_that("F12+F13: source beats name lists; empty remotes never glob-match", {
  root <- tempfile("fork-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  jsonlite::write_json(list(
    R = list(Version = "4.3.2"),
    Packages = list(
      survival = list(Package = "survival", Version = "3.9-0", Source = "GitHub",
                      RemoteUsername = "our-fork", RemoteRepo = "survival"),
      plain = list(Package = "plain", Version = "1.0", Source = "Repository",
                   Repository = "CRAN"),
      prio = list(Package = "prio", Version = "1.0", Source = "Repository",
                  Priority = "recommended")
    )
  ), file.path(root, "renv.lock"), auto_unbox = TRUE)
  writeLines(c("avior: 1", "scope:", '  custom_orgs: ["*"]',
               "policy:", "  weights: { has_news: 1.0 }", "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  cfg <- avior_config_load(root)
  lock <- avior:::read_renv_lock(file.path(root, "renv.lock"))
  cls <- avior:::classify_packages(lock, cfg)
  expect_identical(cls$classification[cls$name == "survival"], "custom") # fork
  expect_identical(cls$classification[cls$name == "plain"], "contributed") # "*" must not match "/"
  expect_identical(cls$classification[cls$name == "prio"], "recommended") # Priority field
})

test_that("F14: an empty Packages section yields an empty inventory, not an error", {
  root <- tempfile("empty-")
  dir.create(file.path(root, "validation"), recursive = TRUE)
  writeLines('{"R": {"Version": "4.3.2"}, "Packages": {}}',
             file.path(root, "renv.lock"))
  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: 1.0 }", "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  inv <- avior_scan(root)
  expect_identical(inv$summary$total, 0L)
})

test_that("F19: argv hygiene — bad --format usage exits 2", {
  root <- local_example_project()
  old <- setwd(root); on.exit(setwd(old), add = TRUE)
  expect_identical(suppressMessages(main(c("scan", "--format"))), 2L)
  expect_identical(suppressMessages(main(c("scan", "--format", "yaml"))), 2L)
  expect_identical(suppressMessages(main(c("scan", "--format", "json",
                                           "--format", "json"))), 2L)
})
