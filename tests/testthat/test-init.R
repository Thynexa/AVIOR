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

test_that("init --ci github generates the workflow deterministically (FR-INIT-3)", {
  root <- tempfile("init-ci-")
  dir.create(root)
  res <- avior_init(root, ci = "github")
  wf <- file.path(root, ".github", "workflows", "avior.yml")
  expect_true(file.exists(wf))
  expect_true(any(grepl(file.path(".github", "workflows", "avior.yml"),
                        res$created, fixed = TRUE)))
  lines <- readLines(wf)
  expect_true(any(grepl('pak::pak("Thynexa/AVIOR")', lines, fixed = TRUE)))
  expect_false(any(grepl('install.packages("avior")', lines, fixed = TRUE)))
  first <- readBin(wf, "raw", file.size(wf))
  # LF-only content, ends with a newline (FR-X-8)
  expect_false(any(first == as.raw(0x0d)))
  expect_identical(first[length(first)], as.raw(0x0a))
  expect_true(any(grepl("avior::main", readLines(wf))))

  # a second run must keep the file byte-identical and report it kept
  res2 <- avior_init(root, ci = "github")
  expect_identical(readBin(wf, "raw", file.size(wf)), first)
  expect_true(any(grepl("workflows", res2$skipped)))
})

test_that("init --ci gitlab generates .gitlab-ci.yml and keeps existing files", {
  root <- tempfile("init-ci-")
  dir.create(root)
  res <- avior_init(root, ci = "gitlab")
  cfgfile <- file.path(root, ".gitlab-ci.yml")
  expect_true(file.exists(cfgfile))
  expect_true(any(grepl(".gitlab-ci.yml", res$created, fixed = TRUE)))
  lines <- readLines(cfgfile)
  expect_true(any(grepl('pak::pak("Thynexa/AVIOR")', lines, fixed = TRUE)))
  expect_false(any(grepl('install.packages("avior")', lines, fixed = TRUE)))

  # an existing (possibly hand-edited) CI file is NEVER overwritten
  writeLines("stages: [mine]", cfgfile)
  res2 <- avior_init(root, ci = "gitlab")
  expect_identical(readLines(cfgfile), "stages: [mine]")
  expect_true(any(grepl(".gitlab-ci.yml", res2$skipped, fixed = TRUE)))
})

test_that("init rejects unsupported ci providers (FR-INIT-3)", {
  root <- tempfile("init-ci-")
  dir.create(root)
  expect_error(avior_init(root, ci = "circleci"), regexp = "github|gitlab",
               class = "avior_error")
  expect_error(avior_init(root, ci = c("github", "gitlab")),
               class = "avior_error")
  # the validation scaffold must not be half-created before the abort
  expect_false(dir.exists(file.path(root, "validation")))
})
