\name{avior_review}
\alias{avior_review}
\title{Generate decision stubs and validate decision completeness (avior review)}
\usage{avior_review(root = ".")}
\arguments{\item{root}{Project root.}}
\value{
\code{list(stubs_created =, findings =)}. Stubs follow PRD 6.3 (including
the reserved \code{assessment_type}/\code{supersedes} fields) and are never
overwritten once created.
}
\description{
For every in-scope package without a decision record, writes a stub
pre-filled with the current score snapshot. Then validates all decisions
(FR-REVIEW-3/4/5): signature, rationale, version freshness, use statements
on medium/high tiers, targeted tests for \code{include_with_tests} and
high-risk packages, and AI dual sign-off.
}
