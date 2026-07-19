\name{avior_scan}
\alias{avior_scan}
\title{Identify and classify project dependencies (avior scan)}
\usage{avior_scan(root = ".")}
\arguments{
  \item{root}{Project root containing the lockfile and \code{validation/}.}
}
\value{
The inventory list, invisibly. Writes \code{validation/inventory.yml}
(git-tracked generated artifact).
}
\description{
Parses \code{renv.lock}, classifies packages (base / recommended /
contributed / custom), detects directly-called packages from project
sources with file:line provenance, applies scope include/exclude
overrides (recorded in-band), and records the lockfile SHA-256 as the
drift baseline (PRD FR-SCAN-1..5). Output ordering follows FR-X-7 and
serialization follows FR-X-8, so repeated runs are byte-identical.
}
\examples{
\dontrun{
# Run from a project that has a renv.lock and a validation/ tree:
avior_init(".")
avior_scan(".")
}
}
