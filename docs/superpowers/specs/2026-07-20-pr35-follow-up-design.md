# PR #35 Follow-up Design

## Context

PR #35 delivered the M2 `test`, `bundle`, `verify`, and English-report
workflow and has already been merged. Its source branch was deleted, so these
corrections must be delivered in a follow-up pull request based on the merge
commit.

## Scope

The follow-up fixes four problems found while independently validating the
merged package:

1. Generated GitHub and GitLab CI configurations try to install `avior` from
   CRAN even though the development package is distributed from GitHub.
2. The fixture-drift test treats an ignored macOS `.DS_Store` file as validation
   content, causing a clean source tree with ordinary Finder metadata to fail.
3. The getting-started vignette still describes M2 as unimplemented and omits
   the `test`, `bundle`, and `verify` workflow.
4. `README.md` and `man/avior_init.Rd` contain stale installation, workflow,
   report-engine, command-list, and CI-provider details.

The unexplained remote GitHub Actions failures are out of scope because GitHub
exposes neither job steps nor logs for those runs. This change will not alter
the repository's primary workflows without a reproducible cause.

## Design

### CI scaffolding

Both generated CI templates will install `pak`, then install
`Thynexa/AVIOR` through `pak`. The surrounding comments will state that an
organisation may replace this with a pinned release or internal repository.
Tests for `avior_init(ci = ...)` will assert that the generated files contain
the GitHub package source and do not contain `install.packages("avior")`.

### Fixture comparison

The fixture file-list helper will exclude only files whose basename is exactly
`.DS_Store`. Other hidden or unexpected files will remain visible to the drift
test. A regression test will create equivalent temporary trees, add
`.DS_Store` to only one tree, and demonstrate that the comparison set remains
equal while an unrelated hidden file remains detectable.

### User documentation

The vignette and README workflow will cover the complete sequence:

`init -> scan -> assess -> review -> test -> check -> bundle -> verify`

They will explain the required test header, the English HTML/DOCX output, the
fail-closed Chinese placeholder, and the manifest anchor. The README will name
the built-in renderer rather than Quarto and will avoid brittle exact test
counts. `man/avior_init.Rd` will document `ci = "github"` and
`ci = "gitlab"`, including the no-overwrite behavior.

## Verification

Implementation will follow a red-green cycle for CI-template and `.DS_Store`
regressions. Completion requires:

- focused tests for init scaffolding and fixture drift;
- the complete testthat suite;
- package build and `R CMD check` using the built tarball;
- inspection of the final diff for unrelated changes.

The follow-up pull request will link to PR #35 and describe the remote CI-log
limitation without claiming that the unexplained checks are fixed.
