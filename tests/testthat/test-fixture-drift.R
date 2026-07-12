# Guards the vendored fixture against drifting from examples/minimal-project.
# Runs only from a source checkout (dev/CI); skipped inside R CMD check where
# examples/ is not shipped.

test_that("vendored fixture matches the repo example (excluding evidence/)", {
  repo <- repo_example_path()
  skip_if(is.na(repo), "repo example not available (running from built package)")

  rel_files <- function(root) {
    f <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
    sort(f[!startsWith(f, "validation/evidence")])
  }
  fix <- fixture_project_path()
  expect_identical(rel_files(fix), rel_files(repo))

  for (f in rel_files(fix)) {
    a <- file.path(fix, f)
    b <- file.path(repo, f)
    expect_true(
      identical(readBin(a, "raw", file.size(a)), readBin(b, "raw", file.size(b))),
      label = paste("fixture file byte-identical to example:", f)
    )
  }
})
