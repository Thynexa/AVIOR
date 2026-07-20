\name{avior_verify}
\alias{avior_verify}
\title{Independently verify bundle integrity (avior verify)}
\usage{avior_verify(bundle)}
\arguments{
\item{bundle}{Path to an evidence bundle: either the bundle directory or a
transport zip produced by \code{avior bundle --zip}.}
}
\value{
\code{list(bundle, source = "directory"|"zip", status = "pass"|"fail",
files_checked, anchor, findings = list(...))}. On success \code{anchor} is
the SHA-256 of \code{MANIFEST.sha256} itself (FR-VERIFY-3) — record it in
the git commit, QMS archive record, or an independent signature. Findings
are typed \code{malformed}, \code{duplicate}, \code{missing},
\code{modified} (with expected/actual hashes), or \code{unexpected}, in a
deterministic order. The CLI maps \code{fail} to exit code 1; an unreadable
or unsafe archive is an execution error (exit 2).
}
\description{
Recomputes the SHA-256 of every file listed in \code{MANIFEST.sha256} and
reports missing, modified, malformed, duplicate, and unexpected files
(FR-VERIFY-1). Runs without any project context — no \code{avior.yml},
no lockfile, no assessment engine — so an auditor needs only the bundle
and this package (FR-VERIFY-2). Zip archives are extracted safely:
absolute paths, drive letters, backslashes, \code{..} traversal, and
duplicate entries are rejected before extraction.

Trust boundary (PRD 5.8): the manifest proves the bundle's internal
consistency only. Whoever can rewrite bundle files can rewrite the
manifest too; the anti-tamper anchor is external — the git commit
containing \code{evidence/}, a QMS archival record, or a signature over
the anchor hash.
}
\examples{
\dontrun{
res <- avior_verify("validation/evidence/bundle-20260708T120000Z")
res$status
res$anchor
}
}
