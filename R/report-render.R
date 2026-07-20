# Validation-report rendering (FR-BUNDLE-2/3, issue #33; English V1).
#
# Boundary contract: avior_bundle() builds one model exclusively from the
# snapshot copies and calls render_report(model, cfg$report, out_dir).
# Everything narrative lives here and in the locale string tables under
# inst/report/locales/ — the bundle compiler holds no report strings, so
# localization can never fork orchestration logic.
#
# Both output formats consume the same locale-neutral block tree built by
# report_document(): HTML and DOCX cannot diverge in content, only in
# serialization.

# -- locale ------------------------------------------------------------------

report_languages <- function() {
  files <- list.files(system.file("report", "locales", package = "avior"),
                      pattern = "\\.yml$")
  sort_c(sub("\\.yml$", "", files))
}

# Fail-closed loader (issue #33): a locale whose status is not `complete`
# (the zh placeholder) must never render — a partial or mixed-language
# report is worse than an explicit error. Also verifies the key set so a
# stale locale cannot silently drop a section.
report_locale_load <- function(language) {
  path <- system.file("report", "locales", paste0(language, ".yml"),
                      package = "avior")
  if (!nzchar(path)) {
    avior_abort(paste0(
      "report.language `", language, "` has no locale table (available: ",
      paste(report_languages(), collapse = ", "), ")"))
  }
  loc <- read_yaml_file(path)
  if (!identical(loc$status, "complete")) {
    avior_abort(paste0(
      "the `", language, "` report template is not yet available (status: ",
      loc$status %||% "unknown", "): it is a schema placeholder awaiting a ",
      "complete translation. Set `report.language: en` in validation/avior.yml ",
      "to render the English report."))
  }
  missing <- setdiff(report_strings_required(), names(loc$strings))
  if (length(missing) > 0) {
    avior_abort(paste0("locale `", language, "` is missing string(s): ",
                       paste(missing, collapse = ", ")))
  }
  loc$strings
}

report_config_validate <- function(report_cfg) {
  formats <- as.character(unlist(report_cfg$formats))
  if (length(formats) == 0) {
    avior_abort("report.formats must name at least one of: html, docx")
  }
  unknown <- setdiff(formats, c("html", "docx"))
  if (length(unknown) > 0) {
    avior_abort(paste0("unsupported report format(s): ",
                       paste(unknown, collapse = ", "),
                       " (supported: html, docx; PDF is out of V1 scope)"))
  }
  strings <- report_locale_load(report_cfg$language)
  list(formats = formats, strings = strings)
}

# "{name}" interpolation; fixed strings, no regex surprises.
str_fill <- function(template, values) {
  for (key in names(values)) {
    template <- gsub(paste0("{", key, "}"),
                     as.character(values[[key]]), template, fixed = TRUE)
  }
  template
}

# -- block tree ---------------------------------------------------------------

blk_heading <- function(level, text) list(type = "heading", level = level, text = text)
blk_para <- function(text) list(type = "para", text = text)
blk_banner <- function(text) list(type = "banner", text = text)
blk_bullets <- function(items) list(type = "bullets", items = items)
blk_table <- function(header, rows) list(type = "table", header = header, rows = rows)
blk_kv <- function(rows) list(type = "kv_table", rows = rows)
blk_page_break <- function() list(type = "page_break")

# The full set of locale keys the renderer consumes; locale files must
# cover every one (checked at load time and by tests).
report_strings_required <- function() {
  c("title", "cover.subtitle", "cover.bundle_id", "cover.generated_at",
    "cover.avior_version", "cover.engine", "cover.r_platform",
    "cover.repositories", "cover.repositories_none", "cover.integrity",
    "cover.integrity_passed", "cover.integrity_failed", "cover.forced_banner",
    "sec1.title", "sec1.body",
    "sec2.title", "sec2.proves", "sec2.not_covered_lead",
    "sec2.not_covered.header_item", "sec2.not_covered.header_owner",
    "sec2.not_covered.iq_oq_pq", "sec2.not_covered.iq_oq_pq_owner",
    "sec2.not_covered.analysis_code", "sec2.not_covered.analysis_code_owner",
    "sec2.not_covered.part11", "sec2.not_covered.part11_owner",
    "sec2.exemption_lead", "sec2.exemption.fact", "sec2.exemption.policy",
    "sec2.force_included", "sec2.excluded",
    "sec3.title", "sec3.body", "sec3.header.package", "sec3.header.version",
    "sec3.header.classification", "sec3.header.role",
    "sec3.header.disposition", "sec3.disposition.assessed",
    "sec3.disposition.version_managed", "sec3.disposition.exempt",
    "sec3.disposition.force_included", "sec3.disposition.excluded",
    "sec4.title", "sec4.thresholds", "sec4.none", "sec4.header.package",
    "sec4.header.score", "sec4.header.tier", "sec4.header.note",
    "sec5.title", "sec5.none", "sec5.header.package", "sec5.header.decision",
    "sec5.header.use_statement", "sec5.header.rationale",
    "sec5.header.reviewed_by",
    "sec6.title", "sec6.body", "sec6.none", "sec6.header.file",
    "sec6.header.package", "sec6.header.tests", "sec6.header.passed",
    "sec6.header.failed", "sec6.header.skipped", "sec6.header.status",
    "sec6.coverage_note",
    "sec7.title", "sec7.r_version", "sec7.platform", "sec7.repositories",
    "sec7.lockfile", "sec7.lockfile_value", "sec7.locale",
    "sec7.blas_lapack", "sec7.container", "sec7.container_none",
    "sec7.session", "sec7.session_value", "sec7.body",
    "appendix_a.title", "appendix_a.body", "appendix_a.header.package",
    "appendix_a.header.version", "appendix_a.header.classification",
    "appendix_a.header.role", "appendix_a.header.score",
    "appendix_a.header.tier", "appendix_a.header.decision",
    "appendix_a.header.tests", "appendix_a.header.status",
    "appendix_b.title", "appendix_b.manifest", "appendix_b.trust",
    "footer", "value.empty", "status.pass", "status.fail")
}

package_disposition <- function(p, s) {
  if (identical(p$role, "transitive")) return(s[["sec3.disposition.version_managed"]])
  if (isTRUE(p$in_scope)) {
    if (isTRUE(p$overridden) &&
        identical(p$override_source, "avior.yml scope.include")) {
      return(s[["sec3.disposition.force_included"]])
    }
    return(s[["sec3.disposition.assessed"]])
  }
  if (identical(p$override_source %||% "", "avior.yml scope.exclude")) {
    return(s[["sec3.disposition.excluded"]])
  }
  s[["sec3.disposition.exempt"]]
}

repositories_label <- function(environment, s) {
  repos <- environment$repositories
  if (length(repos) == 0) return(s[["cover.repositories_none"]])
  paste(vapply(repos, function(r) {
    if (!is.null(r$snapshot)) paste0(r$name, " @ ", r$snapshot) else
      paste0(r$name, " (", r$url, ")")
  }, character(1)), collapse = "; ")
}

# Locale-neutral document structure: model + strings -> block tree.
report_document <- function(model, s) {
  fill <- function(key, ...) str_fill(s[[key]], list(...))
  empty <- s[["value.empty"]]
  or_empty <- function(v) {
    if (is.null(v) || length(v) != 1 || is.na(v) || !nzchar(as.character(v))) {
      empty
    } else {
      as.character(v)
    }
  }
  blocks <- list()
  add <- function(b) blocks[[length(blocks) + 1L]] <<- b

  # cover
  add(blk_heading(1, s[["title"]]))
  add(blk_para(fill("cover.subtitle", project = model$meta$project_name)))
  add(blk_kv(list(
    c(s[["cover.bundle_id"]], model$meta$bundle_id),
    c(s[["cover.generated_at"]], model$meta$generated_at),
    c(s[["cover.avior_version"]], model$meta$avior_version),
    c(s[["cover.engine"]], model$meta$engine_label),
    c(s[["cover.r_platform"]],
      paste0(model$meta$r_version, " / ", model$meta$platform)),
    c(s[["cover.repositories"]], repositories_label(model$environment, s)),
    c(s[["cover.integrity"]],
      if (identical(model$integrity$check, "passed")) {
        s[["cover.integrity_passed"]]
      } else {
        s[["cover.integrity_failed"]]
      })
  )))
  if (isTRUE(model$integrity$forced)) {
    add(blk_banner(fill("cover.forced_banner",
                        n = model$integrity$finding_count,
                        types = paste(model$integrity$finding_types,
                                      collapse = ", "))))
  }

  # 1. methodology
  add(blk_heading(2, s[["sec1.title"]]))
  add(blk_para(s[["sec1.body"]]))

  # 2. scope & boundary (fixed disclaimer section)
  add(blk_heading(2, s[["sec2.title"]]))
  add(blk_para(s[["sec2.proves"]]))
  add(blk_para(s[["sec2.not_covered_lead"]]))
  add(blk_table(
    c(s[["sec2.not_covered.header_item"]], s[["sec2.not_covered.header_owner"]]),
    list(c(s[["sec2.not_covered.iq_oq_pq"]], s[["sec2.not_covered.iq_oq_pq_owner"]]),
         c(s[["sec2.not_covered.analysis_code"]], s[["sec2.not_covered.analysis_code_owner"]]),
         c(s[["sec2.not_covered.part11"]], s[["sec2.not_covered.part11_owner"]]))))
  add(blk_para(s[["sec2.exemption_lead"]]))
  add(blk_bullets(c(s[["sec2.exemption.fact"]], s[["sec2.exemption.policy"]])))
  forced_in <- vapply(
    Filter(function(p) isTRUE(p$overridden) &&
             identical(p$override_source, "avior.yml scope.include"),
           model$inventory$packages),
    function(p) p$name, character(1))
  if (length(forced_in) > 0) {
    add(blk_para(fill("sec2.force_included",
                      packages = paste(sort_c(forced_in), collapse = ", "))))
  }
  excluded <- vapply(
    Filter(function(p) identical(p$override_source %||% "",
                                 "avior.yml scope.exclude"),
           model$inventory$packages),
    function(p) p$name, character(1))
  if (length(excluded) > 0) {
    add(blk_para(fill("sec2.excluded",
                      packages = paste(sort_c(excluded), collapse = ", "))))
  }

  # 3. scope & classification
  add(blk_heading(2, s[["sec3.title"]]))
  add(blk_para(fill("sec3.body",
                    lockfile = model$inventory$lockfile$path,
                    n = model$inventory$summary$total)))
  add(blk_table(
    c(s[["sec3.header.package"]], s[["sec3.header.version"]],
      s[["sec3.header.classification"]], s[["sec3.header.role"]],
      s[["sec3.header.disposition"]]),
    lapply(model$inventory$packages, function(p) {
      c(p$name, p$version, p$classification, p$role,
        package_disposition(p, s))
    })))

  # 4. scoring & thresholds
  add(blk_heading(2, s[["sec4.title"]]))
  if (is.null(model$scores) || length(model$scores$packages) == 0) {
    add(blk_para(s[["sec4.none"]]))
  } else {
    sc <- model$scores
    na_metrics <- as.character(unlist(sc$na_metrics))
    add(blk_para(fill("sec4.thresholds",
                      low_max = avior_format_num(model$policy$policy$risk_tiers$low_max),
                      high_min = avior_format_num(model$policy$policy$risk_tiers$high_min),
                      deep = tolower(as.character(isTRUE(sc$run$deep))),
                      network = tolower(as.character(isTRUE(sc$run$network))),
                      na_metrics = if (length(na_metrics) == 0) empty else
                        paste(na_metrics, collapse = ", "))))
    add(blk_table(
      c(s[["sec4.header.package"]], s[["sec4.header.score"]],
        s[["sec4.header.tier"]], s[["sec4.header.note"]]),
      lapply(sort_c(names(sc$packages)), function(pkg) {
        sp <- sc$packages[[pkg]]
        c(pkg, avior_format_num(sp$score), sp$tier, or_empty(sp$note))
      })))
  }

  # 5. decision summary
  add(blk_heading(2, s[["sec5.title"]]))
  if (length(model$decisions) == 0) {
    add(blk_para(s[["sec5.none"]]))
  } else {
    add(blk_table(
      c(s[["sec5.header.package"]], s[["sec5.header.decision"]],
        s[["sec5.header.use_statement"]], s[["sec5.header.rationale"]],
        s[["sec5.header.reviewed_by"]]),
      lapply(sort_c(names(model$decisions)), function(pkg) {
        d <- model$decisions[[pkg]]
        c(pkg, or_empty(d$decision), or_empty(trimws(d$use_statement %||% "")),
          or_empty(trimws(d$rationale %||% "")), or_empty(d$reviewed_by))
      })))
  }

  # 6. test evidence
  add(blk_heading(2, s[["sec6.title"]]))
  if (is.null(model$tests) || length(model$tests$results) == 0) {
    add(blk_para(s[["sec6.none"]]))
  } else {
    add(blk_para(s[["sec6.body"]]))
    add(blk_table(
      c(s[["sec6.header.file"]], s[["sec6.header.package"]],
        s[["sec6.header.tests"]], s[["sec6.header.passed"]],
        s[["sec6.header.failed"]], s[["sec6.header.skipped"]],
        s[["sec6.header.status"]]),
      lapply(model$tests$results, function(r) {
        # the shared row rule (test_row_passing): all-skipped/zero-test
        # rows must not read PASS in the human-facing report either
        c(r$file, paste(r$package, r$package_version),
          as.character(r$tests %||% 0), as.character(r$passed %||% 0),
          as.character(r$failed %||% 0), as.character(r$skipped %||% 0),
          if (test_row_passing(r)) s[["status.pass"]] else s[["status.fail"]])
      })))
    add(blk_para(s[["sec6.coverage_note"]]))
  }

  # 7. environment & reproducibility
  env <- model$environment
  add(blk_heading(2, s[["sec7.title"]]))
  add(blk_kv(list(
    c(s[["sec7.r_version"]], env$r_version),
    c(s[["sec7.platform"]], env$platform),
    c(s[["sec7.repositories"]], repositories_label(env, s)),
    c(s[["sec7.lockfile"]],
      fill("sec7.lockfile_value",
           path = env$lockfile$path, sha256 = env$lockfile$sha256)),
    c(s[["sec7.locale"]], paste0("LC_COLLATE=", env$locale$LC_COLLATE)),
    c(s[["sec7.blas_lapack"]], paste0(env$blas, " / ", env$lapack)),
    c(s[["sec7.container"]], env$container %||% s[["sec7.container_none"]]),
    c(s[["sec7.session"]], s[["sec7.session_value"]])
  )))
  add(blk_para(s[["sec7.body"]]))

  # appendix A: per-package detail, straight from the traceability matrix
  add(blk_page_break())
  add(blk_heading(2, s[["appendix_a.title"]]))
  add(blk_para(s[["appendix_a.body"]]))
  tr <- model$trace
  add(blk_table(
    c(s[["appendix_a.header.package"]], s[["appendix_a.header.version"]],
      s[["appendix_a.header.classification"]], s[["appendix_a.header.role"]],
      s[["appendix_a.header.score"]], s[["appendix_a.header.tier"]],
      s[["appendix_a.header.decision"]], s[["appendix_a.header.tests"]],
      s[["appendix_a.header.status"]]),
    lapply(seq_len(nrow(tr)), function(i) {
      score <- tr$score[i]
      c(tr$package[i], tr$version[i], tr$classification[i], tr$role[i],
        if (is.na(score)) empty else avior_format_num(score),
        or_empty(tr$tier[i]), or_empty(tr$decision[i]),
        or_empty(tr$test_files[i]), or_empty(tr$test_status[i]))
    })))

  # appendix B: integrity & trust boundary (narrative only — the report is
  # itself inside the manifest, so it must never embed manifest hashes)
  add(blk_page_break())
  add(blk_heading(2, s[["appendix_b.title"]]))
  add(blk_para(s[["appendix_b.manifest"]]))
  add(blk_para(s[["appendix_b.trust"]]))

  add(blk_para(fill("footer", version = model$meta$avior_version)))
  blocks
}

# -- HTML renderer -------------------------------------------------------------

html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}

REPORT_CSS <- c(
  "  body { font: 15px/1.6 -apple-system, \"Segoe UI\", sans-serif;",
  "         max-width: 900px; margin: 2rem auto; padding: 0 1.2rem; color: #1a1a1a; }",
  "  h1 { font-size: 1.7rem; border-bottom: 3px solid #2b5c8a; padding-bottom: .4rem; }",
  "  h2 { font-size: 1.25rem; margin-top: 2rem; color: #2b5c8a;",
  "       border-left: 4px solid #2b5c8a; padding-left: .6rem; }",
  "  table { border-collapse: collapse; width: 100%; margin: .8rem 0; font-size: 14px; }",
  "  th, td { border: 1px solid #cbd5e0; padding: .45rem .6rem; text-align: left; vertical-align: top; }",
  "  th { background: #edf2f7; }",
  "  .meta td:first-child { font-weight: 600; width: 220px; background: #f7fafc; }",
  "  .banner { background: #fef3f2; border: 2px solid #b42318; border-radius: 6px;",
  "            padding: .7rem 1rem; margin: 1rem 0; font-weight: 600; }",
  "  footer { margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid #cbd5e0;",
  "           font-size: 13px; color: #667085; }")

render_report_html <- function(blocks, title, path) {
  out <- c("<!DOCTYPE html>", "<html lang=\"en\">", "<head>",
           "<meta charset=\"utf-8\">",
           paste0("<title>", html_escape(title), "</title>"),
           "<style>", REPORT_CSS, "</style>", "</head>", "<body>")
  n <- length(blocks)
  for (i in seq_len(n)) {
    b <- blocks[[i]]
    is_footer <- identical(i, n)
    out <- c(out, switch(
      b$type,
      heading = paste0("<h", b$level, ">", html_escape(b$text),
                       "</h", b$level, ">"),
      para = if (is_footer) {
        paste0("<footer>", html_escape(b$text), "</footer>")
      } else {
        paste0("<p>", html_escape(b$text), "</p>")
      },
      banner = paste0("<div class=\"banner\">", html_escape(b$text), "</div>"),
      bullets = c("<ul>",
                  vapply(b$items, function(it) {
                    paste0("<li>", html_escape(it), "</li>")
                  }, character(1)),
                  "</ul>"),
      kv_table = c("<table class=\"meta\">",
                   vapply(b$rows, function(r) {
                     paste0("<tr><td>", html_escape(r[1]), "</td><td>",
                            html_escape(r[2]), "</td></tr>")
                   }, character(1)),
                   "</table>"),
      table = c("<table>",
                paste0("<tr>", paste0("<th>", html_escape(b$header), "</th>",
                                      collapse = ""), "</tr>"),
                vapply(b$rows, function(r) {
                  paste0("<tr>", paste0("<td>", html_escape(r), "</td>",
                                        collapse = ""), "</tr>")
                }, character(1)),
                "</table>"),
      page_break = character(0)
    ))
  }
  out <- c(out, "</body>", "</html>")
  write_lines_lf(out, path)
}

# -- boundary ------------------------------------------------------------------

render_report <- function(model, report_cfg, out_dir) {
  validated <- report_config_validate(report_cfg)
  strings <- validated$strings
  blocks <- report_document(model, strings)
  title <- paste0(strings[["title"]], " - ", model$meta$project_name)
  written <- character(0)
  if ("html" %in% validated$formats) {
    render_report_html(blocks, title, file.path(out_dir, "report.html"))
    written <- c(written, "report.html")
  }
  if ("docx" %in% validated$formats) {
    render_report_docx(blocks, title, file.path(out_dir, "report.docx"))
    written <- c(written, "report.docx")
  }
  written
}
