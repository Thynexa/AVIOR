# avior_init scaffolding (FR-INIT-1/2): contract tree, TODO rationale,
# idempotency.

test_that("init creates the validation tree and a loadable skeleton", {
  root <- tempfile("init-")
  dir.create(root)
  res <- avior_init(root)

  expect_true(file.exists(file.path(root, "validation", "avior.yml")))
  expect_true(dir.exists(file.path(root, "validation", "decisions")))
  expect_true(dir.exists(file.path(root, "validation", "tests")))
  expect_true(dir.exists(file.path(root, "validation", ".cache")))
  expect_true(file.exists(file.path(root, "validation", ".gitignore")))
  expect_true(length(res$created) >= 4)
  expect_identical(res$skipped, character(0))

  gi <- readLines(file.path(root, "validation", ".gitignore"))
  expect_true(".cache/" %in% gi)
  expect_true("evidence/*.zip" %in% gi)

  cfg <- avior_config_load(root)
  expect_true(cfg$rationale_todo)   # forces the org to write its rationale
  # default template: metadata/network-tier metrics only (PRD 6.2 note)
  expect_false("covr_coverage" %in% names(cfg$policy$weights))
  expect_true("remote_checks" %in% names(cfg$policy$weights))
})

test_that("init is idempotent: existing files are never overwritten (FR-INIT-2)", {
  root <- tempfile("init-")
  dir.create(root)
  avior_init(root)
  cfgfile <- file.path(root, "validation", "avior.yml")
  writeLines("avior: 1  # hand-edited", cfgfile)

  res <- avior_init(root)
  expect_identical(readLines(cfgfile), "avior: 1  # hand-edited")
  expect_true(any(grepl("avior.yml", res$skipped)))
  expect_identical(res$created, character(0))
})

test_that("init template project name defaults to the directory name", {
  root <- file.path(tempfile("init-"), "my-trial")
  dir.create(root, recursive = TRUE)
  avior_init(root)
  cfg <- avior:::read_yaml_file(file.path(root, "validation", "avior.yml"))
  expect_identical(cfg$project$name, "my-trial")
})
