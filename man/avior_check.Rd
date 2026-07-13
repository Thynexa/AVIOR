\name{avior_check}
\alias{avior_check}
\title{CI gate: drift and completeness checks (avior check)}
\usage{avior_check(root = ".")}
\arguments{\item{root}{Project root.}}
\value{
\code{list(status = "pass"|"fail", findings = list(...))}; each finding
names the package, the defect type, and a fix suggestion (NFR-8). The CLI
maps fail to exit code 1 (FR-X-3).
}
\description{
Read-only (never re-scores, FR-CHECK-4). Aggregates lockfile drift against
the inventory baseline (FR-CHECK-1), policy validity (rationale TODO,
weights vs the static metric registry), decision completeness
(FR-REVIEW-3), test-result freshness including the environment binding
(FR-TEST-2), and \code{excluded_but_present} (PRD v1.6 A6).
}
