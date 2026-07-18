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

# A package project WITHOUT renv.lock: DESCRIPTION is the dependency source
# (FR-SCAN-1 fallback). Deps chosen to exercise classification (MASS is a
# vendored recommended name) and direct-call detection (jsonlite:: in R/).
local_description_project <- function(env = parent.frame()) {
  root <- tempfile("desc-proj-")
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "validation"))
  writeLines(c(
    "Package: descdemo",
    "Version: 0.1.0",
    "Depends: R (>= 4.1), MASS",
    "Imports: jsonlite (>= 1.8.0),",
    "    yaml",
    "LinkingTo: Rcpp"
  ), file.path(root, "DESCRIPTION"))
  writeLines("res <- jsonlite::fromJSON(\"[]\")", file.path(root, "R", "use.R"))
  writeLines(c(
    "avior: 1",
    "project:",
    "  name: descdemo",
    "  validation_dir: validation",
    "policy:",
    "  engine: riskmetric",
    "  weights:",
    "    has_news: 1.0",
    "  rationale: fixture rationale for DESCRIPTION-fallback tests"
  ), file.path(root, "validation", "avior.yml"))
  withr_defer_dir(root, env)
  root
}

# Minimal withr::defer replacement (avoid adding withr to Suggests).
withr_defer_dir <- function(path, env) {
  call <- bquote(unlink(.(path), recursive = TRUE, force = TRUE))
  do.call(on.exit, list(call, add = TRUE), envir = env)
}

# Simulate a human re-reviewing after a re-assessment: rewrite each decision's
# score_snapshot line to match the current scores.yml (engine + score + tier),
# so a consistent project has no stale_score finding. Used by pipeline tests
# that re-assess with a mock engine whose id/scores differ from the fixture's
# hand-authored snapshots.
resnapshot_decisions <- function(root) {
  vdir <- file.path(root, "validation")
  scores <- avior:::read_yaml_file(file.path(vdir, "scores.yml"))
  eng <- trimws(paste(scores$engine$id, scores$engine$version))
  for (f in list.files(file.path(vdir, "decisions"), pattern = "\\.yml$",
                       full.names = TRUE)) {
    d <- avior:::read_yaml_file(f)
    sp <- scores$packages[[d$package]]
    if (is.null(sp)) next
    lines <- readLines(f, encoding = "UTF-8")
    i <- grep("^score_snapshot:", lines)
    lines[i] <- sprintf(
      'score_snapshot: { score: %s, tier: %s, scored_at: "%s", engine: "%s" }',
      avior:::avior_format_num(sp$score), sp$tier, scores$scored_at, eng)
    writeLines(lines, f)
  }
}
