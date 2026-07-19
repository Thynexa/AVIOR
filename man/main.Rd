\name{main}
\alias{main}
\title{CLI entry point}
\usage{main(argv = commandArgs(trailingOnly = TRUE))}
\arguments{
  \item{argv}{Command-line arguments, e.g. \code{c("scan", "--format", "json")}.}
}
\value{
Invisibly, the process exit code per FR-X-3: 0 success, 1 business
failure, 2 execution error. \code{inst/exec/avior} passes it to
\code{quit()}.
}
\description{
Dispatches the avior CLI commands. \code{--format json} emits a
machine-readable result envelope (FR-X-2).
}
\examples{
\dontrun{
# Equivalent to the `avior` CLI shim:
main(c("scan", "--format", "json"))
}
}
