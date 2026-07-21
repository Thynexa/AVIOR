# avior — validation evidence compiler for R package environments.
#
# Layering (see docs/PRD.md for the architecture and milestone context):
#   canonical.R  — FR-X-8 canonical serialization; every artifact goes through it
#   utils.R      — hashing, error classes, shared helpers
#   config.R     — avior.yml loading + schema validation
#   lockfile.R   — renv.lock parsing + package classification
#   scan-calls.R — static detection of directly-called packages
#   scan.R/init.R/... — the CLI commands (avior_scan, avior_init, ...)
#
# File contracts are frozen in docs/PRD.md §6; do not change generated
# artifact shapes here without a PRD revision.
NULL
