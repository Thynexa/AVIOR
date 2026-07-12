# Test fixture helpers.
#
# The primary fixture is a trimmed copy of examples/minimal-project (the M0
# hand-assembled sample) vendored under tests/testthat/fixtures/ so that
# R CMD check remains self-contained (.Rbuildignore excludes examples/).
# test-fixture-drift.R guards the copy against drifting from the repo example.

fixture_project_path <- function() {
  testthat::test_path("fixtures", "minimal-project")
}

# Path to the repo-level example, when running from a source checkout
# (dev / CI). Returns NA inside R CMD check where examples/ is not shipped.
repo_example_path <- function() {
  override <- Sys.getenv("AVIOR_EXAMPLE_DIR", unset = "")
  if (nzchar(override)) return(override)
  p <- testthat::test_path("..", "..", "examples", "minimal-project")
  if (dir.exists(p)) normalizePath(p) else NA_character_
}

# Copy the fixture project into a fresh temp dir; cleaned up with the test.
local_example_project <- function(env = parent.frame()) {
  src <- fixture_project_path()
  stopifnot(dir.exists(src))
  root <- file.path(tempfile("avior-fixture-"), "minimal-project")
  dir.create(dirname(root), recursive = TRUE)
  ok <- file.copy(src, dirname(root), recursive = TRUE)
  stopifnot(all(ok))
  withr_defer_dir(dirname(root), env)
  root
}

# Minimal withr::defer replacement (avoid adding withr to Suggests).
withr_defer_dir <- function(path, env) {
  call <- bquote(unlink(.(path), recursive = TRUE, force = TRUE))
  do.call(on.exit, list(call, add = TRUE), envir = env)
}
