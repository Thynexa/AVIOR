# avior_scan orchestration (FR-SCAN-1..5): inventory generation, scope
# logic, overrides, determinism, and semantic equality with the M0 example.

test_that("scan on the fixture matches the hand-built inventory semantically", {
  root <- local_example_project()
  unlink(file.path(root, "validation", "inventory.yml"))
  avior_scan(root)

  got <- avior:::read_yaml_file(file.path(root, "validation", "inventory.yml"))
  want <- avior:::read_yaml_file(file.path(fixture_project_path(),
                                           "validation", "inventory.yml"))

  expect_identical(got$avior, want$avior)
  expect_identical(got$generated_by, want$generated_by)
  expect_identical(got$lockfile, want$lockfile)
  expect_identical(got$summary, want$summary)

  expect_identical(length(got$packages), length(want$packages))
  for (i in seq_along(want$packages)) {
    w <- want$packages[[i]]
    g <- got$packages[[i]]
    for (field in setdiff(names(w), "note")) {
      expect_identical(g[[field]], w[[field]],
                       label = paste0("packages[", i, "]$", field, " (",
                                      w$name, ") got"))
    }
  }
})

test_that("scan output is byte-identical across reruns (FR-X-7/8)", {
  root <- local_example_project()
  inv <- file.path(root, "validation", "inventory.yml")
  avior_scan(root)
  first <- readBin(inv, "raw", file.size(inv))
  avior_scan(root)
  expect_identical(readBin(inv, "raw", file.size(inv)), first)
})

test_that("forced inclusion of a recommended package is recorded (FR-SCAN-4)", {
  root <- local_example_project()
  avior_scan(root)
  inv <- avior:::read_yaml_file(file.path(root, "validation", "inventory.yml"))
  surv <- Filter(function(p) p$name == "survival", inv$packages)[[1]]
  expect_identical(surv$classification, "recommended")
  expect_true(surv$in_scope)
  expect_true(surv$overridden)
  expect_identical(surv$override_source, "avior.yml scope.include")
})

test_that("recommended packages are exempt by default; exclude is recorded", {
  root <- local_example_project()
  cfgfile <- file.path(root, "validation", "avior.yml")
  txt <- readLines(cfgfile)
  txt <- sub("  include: \\[survival\\].*", "  include: []", txt)
  txt <- sub("  exclude: \\[\\]", "  exclude: [jsonlite]", txt)
  writeLines(txt, cfgfile)

  avior_scan(root)
  inv <- avior:::read_yaml_file(file.path(root, "validation", "inventory.yml"))
  by_name <- function(n) Filter(function(p) p$name == n, inv$packages)[[1]]

  surv <- by_name("survival")
  expect_false(surv$in_scope)          # exempt again without scope.include
  expect_null(surv$overridden)

  js <- by_name("jsonlite")
  expect_false(js$in_scope)
  expect_true(js$overridden)
  expect_identical(js$override_source, "avior.yml scope.exclude")

  expect_identical(inv$summary$in_scope_assessed, 2L)   # lme4 + mvtnorm
  expect_identical(inv$summary$recommended_exempt, 1L)  # survival
  expect_identical(inv$summary$force_included, 0L)
})

test_that("transitive provenance names the requiring package", {
  root <- local_example_project()
  avior_scan(root)
  inv <- avior:::read_yaml_file(file.path(root, "validation", "inventory.yml"))
  minqa <- Filter(function(p) p$name == "minqa", inv$packages)[[1]]
  expect_identical(minqa$role, "transitive")
  expect_false(minqa$in_scope)
  expect_identical(minqa$source, "lme4 Requirements")
})

test_that("scan records the lockfile sha256 drift baseline (FR-SCAN-5)", {
  root <- local_example_project()
  avior_scan(root)
  inv <- avior:::read_yaml_file(file.path(root, "validation", "inventory.yml"))
  expect_identical(inv$lockfile$sha256,
                   avior:::sha256_file(file.path(root, "renv.lock")))
})

# -- DESCRIPTION fallback (FR-SCAN-1, #22) ------------------------------------

test_that("scan falls back to DESCRIPTION and records the source", {
  root <- local_description_project()
  inv <- avior_scan(root)

  expect_identical(inv$lockfile$path, "DESCRIPTION")
  expect_identical(inv$lockfile$sha256,
                   avior:::sha256_file(file.path(root, "DESCRIPTION")))
  names <- vapply(inv$packages, function(p) p$name, character(1))
  expect_identical(names, c("MASS", "Rcpp", "jsonlite", "yaml"))

  by_name <- stats::setNames(inv$packages, names)
  # no pinned versions in this source
  expect_identical(by_name$jsonlite$version, "")
  # classification still applies (vendored recommended set by name)
  expect_identical(by_name$MASS$classification, "recommended")
  expect_identical(by_name$jsonlite$classification, "contributed")
  # direct detection via R/ source calls keeps working
  expect_identical(by_name$jsonlite$role, "direct")
  expect_match(by_name$jsonlite$source, "use.R", fixed = TRUE)
  # a declared dependency without call-site evidence falls back to the
  # dependency source file, not the literal "renv.lock"
  expect_identical(by_name$yaml$role, "transitive")
  expect_identical(by_name$yaml$source, "DESCRIPTION")
})

test_that("DESCRIPTION-based scan output is deterministic across reruns", {
  root <- local_description_project()
  avior_scan(root)
  p <- file.path(root, "validation", "inventory.yml")
  first <- readBin(p, "raw", file.size(p))
  avior_scan(root)
  expect_identical(readBin(p, "raw", file.size(p)), first)
})

test_that("scan keeps failing closed when no dependency source exists", {
  root <- local_description_project()
  unlink(file.path(root, "DESCRIPTION"))
  expect_error(avior_scan(root), regexp = "lockfile not found",
               class = "avior_error")
})

test_that("scan aborts on a malformed DESCRIPTION fallback", {
  root <- local_description_project()
  writeLines("Title: not a package", file.path(root, "DESCRIPTION"))
  expect_error(avior_scan(root), class = "avior_error")
})

test_that("renv.lock stays authoritative when both sources exist", {
  root <- local_example_project()
  writeLines(c("Package: shadow", "Imports: nothingreal"),
             file.path(root, "DESCRIPTION"))
  inv <- avior_scan(root)
  expect_identical(inv$lockfile$path, "renv.lock")
})

# -- inventory ownership across rescans (#26) ---------------------------------

test_that("rescan preserves the supported note: annotation (#26)", {
  root <- local_example_project()
  p <- file.path(root, "validation", "inventory.yml")
  # the fixture (frozen M0 example) ships hand-written notes on minqa and
  # survival: a rescan must carry them over, not discard them
  expect_no_warning(avior_scan(root))
  inv <- avior:::read_yaml_file(p)
  by_name <- stats::setNames(
    inv$packages, vapply(inv$packages, function(x) x$name, character(1)))
  expect_match(by_name$minqa$note, "间接依赖")
  expect_true(nzchar(by_name$survival$note))
  expect_null(by_name$jsonlite$note)

  # rescans stay deterministic with notes present
  first <- readBin(p, "raw", file.size(p))
  expect_no_warning(avior_scan(root))
  expect_identical(readBin(p, "raw", file.size(p)), first)

  # a note whose package left the dependency source disappears with its row
  # (drift handling owns that lifecycle), while others keep theirs
  lock <- file.path(root, "renv.lock")
  parsed <- jsonlite::fromJSON(lock, simplifyVector = FALSE)
  parsed$Packages$minqa <- NULL
  writeLines(jsonlite::toJSON(parsed, auto_unbox = TRUE), lock)
  expect_no_warning(avior_scan(root))
  inv <- avior:::read_yaml_file(p)
  names2 <- vapply(inv$packages, function(x) x$name, character(1))
  expect_false("minqa" %in% names2)
  by_name2 <- stats::setNames(inv$packages, names2)
  expect_true(nzchar(by_name2$survival$note))
})

test_that("rescan warns before discarding unsupported inventory fields (#26)", {
  root <- local_example_project()
  avior_scan(root)
  p <- file.path(root, "validation", "inventory.yml")
  pristine <- readBin(p, "raw", file.size(p))

  # an UNSUPPORTED hand-added key: the file is machine-owned, so the rescan
  # rewrites it, but never silently — the warning names the package, the
  # field, and where human input belongs (note: / decision records)
  txt <- readLines(p)
  i <- grep("name: jsonlite", txt)[1]
  txt[i] <- sub("\\}$", ", reviewer_remark: looks fine}", txt[i])
  writeLines(txt, p)
  expect_warning(avior_scan(root), "reviewer_remark.*decision records")

  # deterministic: the rescan result is byte-identical to the pristine scan
  expect_identical(readBin(p, "raw", file.size(p)), pristine)

  # a clean rescan stays silent
  expect_no_warning(avior_scan(root))
})
