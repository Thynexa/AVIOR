# The report-renderer boundary consumed by avior_bundle (FR-BUNDLE-2/3).
# The bundle compiler passes a single model (built exclusively from the
# snapshot copies) plus the report configuration; everything narrative —
# section structure, locale strings, HTML/DOCX serialization — lives
# behind this function so localization can never fork orchestration logic.
#
# Rendering lands with the report milestone (#33); until then the bundle
# contains every non-report artifact and the boundary returns no files.
render_report <- function(model, report_cfg, out_dir) {
  character(0)
}
