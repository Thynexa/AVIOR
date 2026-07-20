\name{avior_test}
\alias{avior_test}
\title{Run targeted tests and record test evidence (avior test)}
\usage{avior_test(root = ".", coverage = FALSE)}
\arguments{
\item{root}{Project root.}
\item{coverage}{Collect covr coverage as a disclosed reference metric
(\code{coverage_ref}) when the covr package is available (FR-TEST-3).
Never a gate: any coverage failure omits the field and the run proceeds.}
}
\value{
\code{list(status = "ok"|"fail", results = list(...), environment =
list(...), testthat_version, path)}; one result row per test file with
pass/fail/skip counts and duration. A failing targeted test — or a file
whose run produced no passing test at all (all skipped, or zero
\code{test_that()} blocks) — maps to CLI exit code 1 (business failure):
a run without passing evidence is not evidence. Malformed inputs or a
runner crash map to exit code 2 (FR-X-3).
}
\description{
Discovers testthat files under \code{validation/tests/}, maps every file
to its package through the required \code{# avior-package: <pkg>} header
(missing, ambiguous, malformed, or out-of-scope mappings are execution
errors naming every offending file, FR-TEST-1), runs them, and writes
canonical \code{validation/test-results.yml} for consumption by
\code{avior check} and \code{avior bundle} (FR-TEST-2).

Results are bound to the runtime environment: the tested package version
(the installed \code{DESCRIPTION} \code{Version} literal, so lockfile
forms such as \code{3.8-6} are preserved verbatim), the current lockfile
SHA-256, and the R version/platform. \code{avior check} treats a version
or lockfile mismatch as stale evidence, comparing versions with R's
\code{package_version} semantics (\code{.} and \code{-} are
interchangeable separators).
\code{run_at} and \code{duration_s} are measured values; all other output
is deterministic (\code{SOURCE_DATE_EPOCH} fixes \code{run_at} for
reproducible rebuilds, FR-X-8).
}
\examples{
\dontrun{
res <- avior_test(".")
res$status
}
}
