\name{avior_bundle}
\alias{avior_bundle}
\title{Compile an immutable validation evidence bundle (avior bundle)}
\usage{avior_bundle(root = ".", force = FALSE, zip = FALSE)}
\arguments{
\item{root}{Project root.}
\item{force}{Compile even when the pre-compilation \code{avior check}
gate fails (FR-BUNDLE-6). The failure is disclosed machine-readably in
\code{BUNDLE.yml} (\code{integrity_check: failed}, \code{forced: true},
finding count and types) and prominently on the report cover page.}
\item{zip}{Additionally write \code{bundle-<UTC>.zip} next to the bundle
directory. The zip is a transport artifact, not the archival form
(FR-BUNDLE-1): it is gitignored by \code{avior init} and deterministically
rebuildable under \code{SOURCE_DATE_EPOCH}.}
}
\value{
On success \code{list(status = "ok", bundle_id, path, integrity_check,
forced, files, report_files, counts, zip)}. When the check gate blocks
compilation, \code{list(status = "fail", findings, message)} — the CLI
maps this to exit code 1. Timestamp collisions with an existing bundle
are execution errors (exit 2); existing bundles are never overwritten.
}
\description{
Runs the equivalent of \code{avior check}, then snapshots the project's
validation state into a new immutable
\code{validation/evidence/bundle-<UTC timestamp>/} directory (FR-BUNDLE-1):
byte-identical copies of \code{avior.yml}, \code{inventory.yml},
\code{scores.yml}, \code{test-results.yml} and \code{decisions/} under
\code{snapshot/}; \code{traceability.csv} in the PRD 6.5 column schema
(transitive rows carry \code{version_managed}; out-of-scope direct rows
\code{exempt} or \code{excluded}); \code{environment.json} and
\code{session-info.txt} (FR-BUNDLE-5, with \code{"unknown"} fallbacks and
an honest \code{null} container digest); \code{BUNDLE.yml} metadata; and
a path-sorted \code{MANIFEST.sha256} covering every file except itself.

For identical inputs the data artifacts are byte-identical;
\code{SOURCE_DATE_EPOCH} additionally fixes the embedded timestamps
(FR-BUNDLE-8). Verify any bundle independently with
\code{\link{avior_verify}}. \code{BUNDLE.yml}'s \code{integrity_check} is
a generation-time self-attestation, not a trust root (PRD 5.8).
}
\examples{
\dontrun{
res <- avior_bundle(".", zip = TRUE)
res$path
avior_verify(res$path)
}
}
