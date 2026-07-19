\name{avior_init}
\alias{avior_init}
\title{Scaffold the validation/ directory (avior init)}
\usage{avior_init(root = ".", ci = NULL)}
\arguments{
  \item{root}{Project root in which to create \code{validation/}.}
  \item{ci}{Reserved for FR-INIT-3 (CI workflow generation); must be NULL.}
}
\value{
Invisibly, \code{list(created =, skipped =)}. Existing files are never
overwritten (FR-INIT-2).
}
\description{
Creates the contract tree of PRD 6.1: \code{validation/avior.yml} skeleton
(default weights use metadata/network-tier metrics only; rationale is a
TODO that makes \code{avior check} fail until the organisation records its
reasoning), \code{decisions/}, \code{tests/}, \code{.cache/} and a
\code{.gitignore} covering the cache and transport zips.
}
\examples{
proj <- file.path(tempdir(), "avior-demo")
dir.create(proj, showWarnings = FALSE)
avior_init(proj)
list.files(file.path(proj, "validation"))
}
