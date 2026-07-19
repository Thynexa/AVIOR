\name{avior_assess}
\alias{avior_assess}
\title{Score in-scope packages through the engine adapter (avior assess)}
\usage{avior_assess(root = ".", only = NULL, deep = FALSE, engine = NULL,
             refresh_na = TRUE, network_available = TRUE)}
\arguments{
  \item{root}{Project root.}
  \item{only}{Optional package names to re-score fresh (FR-ASSESS-5).}
  \item{deep}{Run execution-tier metrics (e.g. covr_coverage) too. Off by
    default; skipped metrics are NA with cause "execution" (PRD 7.2).}
  \item{engine}{An \code{avior_engine} to use instead of the configured one
    (used by tests).}
  \item{refresh_na}{Re-score cache hits whose NAs have cause "network" when
    the network is available (FR-X-5).}
  \item{network_available}{Whether network metrics are resolvable now.}
}
\value{
The scores structure, invisibly. Writes \code{validation/scores.yml}
including the \code{run: \{deep, network\}} disclosure. \code{na_action:
fail} raises \code{avior_na_error} (exit 1).
}
\description{
Aggregates engine metric "goodness" values into a 0-1 risk score
(\code{risk = 1 - weighted.mean}) per the policy weights, maps risk tiers,
and maintains the NA-cause-aware score cache under
\code{validation/.cache/}.
}
\examples{
\dontrun{
# Requires the riskmetric engine (install.packages("riskmetric")) and,
# for network-tier metrics, connectivity:
avior_scan(".")
avior_assess(".")
avior_assess(".", only = "jsonlite", deep = TRUE)
}
}
