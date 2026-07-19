\name{avior_config_load}
\alias{avior_config_load}
\title{Load and validate the project validation policy (avior.yml)}
\usage{avior_config_load(root = ".")}
\arguments{
  \item{root}{Project root; the policy is read from \code{<root>/validation/avior.yml}.}
}
\value{
An \code{avior_config} list: user settings merged over PRD 6.2 defaults,
plus \code{$root}, \code{$paths$validation} and the \code{$rationale_todo}
flag consumed by \code{avior check}. Hard schema violations raise an error
of class \code{avior_config_error}.
}
\description{
Reads the policy-as-code file that governs scanning, scoring and decision
depth (PRD FR-X-1). Defaults are applied for omitted fields; the weights,
risk tiers and na_action fields are validated strictly.
}
\examples{
proj <- file.path(tempdir(), "avior-demo-config")
dir.create(proj, showWarnings = FALSE)
avior_init(proj)
cfg <- avior_config_load(proj)
cfg$policy$engine
}
