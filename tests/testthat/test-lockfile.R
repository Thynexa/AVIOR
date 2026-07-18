# renv.lock parsing + base/recommended/contributed/custom classification
# (FR-SCAN-1, FR-SCAN-2).

write_lock <- function(packages) {
  root <- tempfile("lock-")
  dir.create(root)
  lock <- list(
    R = list(Version = "4.3.2"),
    Packages = packages
  )
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE)
  root
}

test_that("read_renv_lock parses the fixture lockfile", {
  root <- local_example_project()
  lock <- avior:::read_renv_lock(file.path(root, "renv.lock"))
  expect_s3_class(lock, "data.frame")
  expect_identical(nrow(lock), 5L)
  expect_setequal(lock$name, c("jsonlite", "lme4", "minqa", "mvtnorm", "survival"))
  expect_identical(lock$version[lock$name == "survival"], "3.5-7")
  expect_identical(attr(lock, "r_version"), "4.3.2")
})

test_that("read_renv_lock errors with avior_error on missing/malformed input", {
  expect_error(avior:::read_renv_lock(tempfile()), class = "avior_error")
  p <- tempfile()
  writeLines("not json {", p)
  expect_error(avior:::read_renv_lock(p), class = "avior_error")
  p2 <- tempfile()
  writeLines('{"R": {"Version": "4.3.2"}}', p2)  # no Packages
  expect_error(avior:::read_renv_lock(p2), class = "avior_error")
})

test_that("classification: base, recommended, contributed", {
  root <- local_example_project()
  cfg <- avior_config_load(root)
  lock <- avior:::read_renv_lock(file.path(root, "renv.lock"))
  cls <- avior:::classify_packages(lock, cfg)
  expect_identical(cls$classification[cls$name == "survival"], "recommended")
  expect_identical(cls$classification[cls$name == "jsonlite"], "contributed")
  expect_identical(cls$classification[cls$name == "minqa"], "contributed")
})

test_that("classification: custom via renv Source and via custom_orgs glob", {
  root <- write_lock(list(
    gh = list(Package = "gh", Version = "1.0", Source = "GitHub",
              RemoteUsername = "some-org", RemoteRepo = "gh"),
    local = list(Package = "local", Version = "0.1", Source = "Local"),
    ours = list(Package = "ours", Version = "0.2", Source = "Repository",
                Repository = "CRAN",
                RemoteUsername = "our-gh-org", RemoteRepo = "ours"),
    plain = list(Package = "plain", Version = "1.1", Source = "Repository",
                 Repository = "CRAN"),
    Matrix = list(Package = "Matrix", Version = "1.6-5", Source = "Repository")
  ))
  dir.create(file.path(root, "validation"))
  writeLines(c("avior: 1",
               "scope:",
               '  custom_orgs: ["our-gh-org/*"]',
               "policy:",
               "  weights: { has_news: 1.0 }",
               "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  cfg <- avior_config_load(root)
  lock <- avior:::read_renv_lock(file.path(root, "renv.lock"))
  cls <- avior:::classify_packages(lock, cfg)
  expect_identical(cls$classification[cls$name == "gh"], "custom")     # GitHub source
  expect_identical(cls$classification[cls$name == "local"], "custom")  # Local source
  expect_identical(cls$classification[cls$name == "ours"], "custom")   # org glob match
  expect_identical(cls$classification[cls$name == "plain"], "contributed")
  expect_identical(cls$classification[cls$name == "Matrix"], "recommended")
})

test_that("base packages classify as base", {
  root <- write_lock(list(
    stats = list(Package = "stats", Version = "4.3.2", Source = "Repository")
  ))
  dir.create(file.path(root, "validation"))
  writeLines(c("avior: 1", "policy:",
               "  weights: { has_news: 1.0 }", "  rationale: ok"),
             file.path(root, "validation", "avior.yml"))
  cfg <- avior_config_load(root)
  lock <- avior:::read_renv_lock(file.path(root, "renv.lock"))
  cls <- avior:::classify_packages(lock, cfg)
  expect_identical(cls$classification, "base")
})

# -- DESCRIPTION fallback (FR-SCAN-1, #22) ------------------------------------

test_that("read_description_deps inventories Depends/Imports/LinkingTo", {
  root <- local_description_project()
  df <- avior:::read_description_deps(file.path(root, "DESCRIPTION"))
  # R itself excluded; constraint stripped; continuation line parsed;
  # C-locale name order
  expect_identical(df$name, c("MASS", "Rcpp", "jsonlite", "yaml"))
  expect_identical(df$version, rep("", 4L))
  expect_identical(df$source, rep("", 4L))
  expect_identical(unclass(df$requirements), rep(list(character(0)), 4L))
})

test_that("read_description_deps deduplicates across fields", {
  path <- tempfile("DESCRIPTION-")
  writeLines(c("Package: demo", "Depends: jsonlite", "Imports: jsonlite (>= 1.0)"),
             path)
  df <- avior:::read_description_deps(path)
  expect_identical(df$name, "jsonlite")
})

test_that("read_description_deps fails closed on malformed input", {
  missing <- tempfile("DESCRIPTION-")
  expect_error(avior:::read_description_deps(missing), class = "avior_error")

  not_a_pkg <- tempfile("DESCRIPTION-")
  writeLines("Title: no package field", not_a_pkg)
  expect_error(avior:::read_description_deps(not_a_pkg),
               regexp = "no Package field", class = "avior_error")

  bad_name <- tempfile("DESCRIPTION-")
  writeLines(c("Package: demo", "Imports: 1badname"), bad_name)
  expect_error(avior:::read_description_deps(bad_name),
               regexp = "malformed dependency", class = "avior_error")
})

test_that("resolve_dep_source prefers renv.lock and fails closed when both absent", {
  root <- local_description_project()
  src <- avior:::resolve_dep_source(root, "renv.lock")
  expect_identical(src$path, "DESCRIPTION")

  writeLines('{"Packages": {}}', file.path(root, "renv.lock"))
  src <- avior:::resolve_dep_source(root, "renv.lock")
  expect_identical(src$path, "renv.lock")

  empty <- tempfile("empty-")
  dir.create(empty)
  expect_error(avior:::resolve_dep_source(empty, "renv.lock"),
               regexp = "DESCRIPTION fallback", class = "avior_error")
})
