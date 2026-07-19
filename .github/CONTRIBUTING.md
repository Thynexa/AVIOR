# Contributing to AVIOR

Thanks for your interest in improving AVIOR. This document describes how to
propose changes and how the project is developed.

## Design baseline

AVIOR is developed against a frozen product requirements document,
[`docs/PRD.md`](../docs/PRD.md). **The PRD is the development baseline.** Every
change is scoped against it, and any change that conflicts with the three design
axioms in §2 of the README must first amend the axioms themselves, with the
rationale recorded in the pull request.

In particular, the generated-artifact file contracts (PRD §6) are frozen: do not
change the shape of a generated artifact (`inventory.yml`, `scores.yml`,
`decisions/*.yml`, reports, manifest) without a PRD revision in the same or a
prior pull request. Determinism is a hard requirement — repeated runs over an
unchanged project must be byte-identical (FR-X-7 / FR-X-8).

## Development workflow

1. **Fork and branch.** Create a topic branch from `main`.
2. **Environment.** The project uses [`renv`](https://rstudio.github.io/renv/).
   Run `renv::restore()` to reproduce the pinned toolchain from `renv.lock`.
3. **Test-driven.** AVIOR is built test-first. Add or update tests under
   `tests/testthat/` for any behavioural change, and keep fixtures in
   `tests/testthat/fixtures/` in sync (there is a `test-fixture-drift.R` guard).
4. **Run the checks locally** before opening a pull request:

   ```r
   devtools::test()          # testthat 3e suite
   lintr::lint_package()     # correctness-tagged lints (see .lintr)
   devtools::check()         # R CMD check --as-cran, all clean
   covr::package_coverage()  # coverage must stay at or above the 80% gate
   ```

5. **Documentation.** The `NAMESPACE` and the `man/*.Rd` pages are
   **hand-maintained** (this is deliberate — see the note at the top of
   `NAMESPACE`). When you add or change an exported function, update its `.Rd`
   page and the `NAMESPACE` export list in the same change.
6. **Changelog.** Add a user-facing entry to `NEWS.md` under the development
   heading.

## Commit and pull-request conventions

* Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/)
  style already used in the history, e.g. `fix(engine): …`, `docs: …`,
  `test(scan): …`.
* Keep pull requests focused and reference the relevant PRD functional
  requirement (e.g. `FR-SCAN-3`) or issue number where applicable.
* CI must be green on all platforms (Linux / macOS / Windows and the R 4.1
  floor), plus lint and coverage, before a pull request is merged.

## Reporting bugs and requesting features

Please use the issue templates under
[`.github/ISSUE_TEMPLATE`](./ISSUE_TEMPLATE). For anything security-sensitive,
follow [`SECURITY.md`](./SECURITY.md) instead of opening a public issue.

## Code of Conduct

By participating in this project you agree to abide by the
[Code of Conduct](./CODE_OF_CONDUCT.md).
