\name{avior_init}
\alias{avior_init}
\title{Scaffold the validation/ directory (avior init)}
\usage{avior_init(root = ".", ci = NULL)}
\arguments{
  \item{root}{Project root in which to create \code{validation/}.}
  \item{ci}{Optional CI provider: \code{NULL} (no workflow),
  \code{"github"}, or \code{"gitlab"}. The generated workflow installs the
  development package from GitHub and runs the read-only \code{avior check}
  gate; pin or replace the installation source for controlled use.}
}
\value{
Invisibly, \code{list(created =, skipped =)}. Existing files are never
overwritten (FR-INIT-2).
}
\description{
Creates the contract tree of PRD 6.1: \code{validation/avior.yml} skeleton
(default weights use metadata/network-tier metrics only; rationale is a
TODO that makes \code{avior check} fail until the organisation records its
reasoning), \code{decisions/}, \code{tests/}, \code{evidence/},
\code{.cache/} and a \code{.gitignore} covering the cache and transport zips.
With \code{ci = "github"}, also creates
\code{.github/workflows/avior.yml}; with \code{ci = "gitlab"}, creates
\code{.gitlab-ci.yml}. Existing policy, ignore, and workflow files are never
overwritten.
}
\examples{
proj <- file.path(tempdir(), "avior-demo")
dir.create(proj, showWarnings = FALSE)
avior_init(proj)
list.files(file.path(proj, "validation"))
\dontrun{
avior_init(".", ci = "github")
avior_init(".", ci = "gitlab")
}
}
