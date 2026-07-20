# avior review — decision records (FR-REVIEW-1..5). Stubs for in-scope
# packages without a decision; completeness validation shared with check.

DECISION_ENUM <- c("include", "include_with_tests", "exclude")

read_scores <- function(cfg) {
  path <- file.path(cfg$paths$validation, "scores.yml")
  if (!file.exists(path)) {
    avior_abort(paste0("scores not found: ", path, " (run `avior assess` first)"))
  }
  # every failure mode of this semantic boundary is an avior_error: the
  # yaml parser throws a plain simpleError, which would otherwise slip
  # past callers that fail closed on avior_error (review_findings)
  scores <- tryCatch(read_yaml_file(path), error = function(e) {
    avior_abort(paste0("cannot parse ", path, ": ", conditionMessage(e),
                       "; re-run `avior assess`"))
  })
  # FR-X-6 at the semantic read boundary (same rule as read_inventory)
  if (!is.list(scores) || !avior_schema_v1(scores$avior)) {
    avior_abort(paste0(path, " has a missing or unsupported schema version ",
                       "(expected avior: 1); re-run `avior assess`"))
  }
  scores
}

decision_path <- function(cfg, pkg) {
  file.path(cfg$paths$validation, "decisions", paste0(pkg, ".yml"))
}

# Decision stub per PRD 6.3 (v1.6 schema, incl. reserved V2 fields).
write_decision_stub <- function(cfg, pkg, version, snapshot) {
  stub <- list(
    avior = 1L,
    package = pkg,
    version = version,
    score_snapshot = yaml_flow(snapshot),
    use_statement = "",
    decision = "",
    rationale = "",
    tests = yaml_seq(character(0)),
    reviewed_by = "",
    date = "",
    ai_assisted = FALSE,
    confirmed_by = NULL,
    assessment_type = "initial",
    supersedes = NULL
  )
  dir.create(dirname(decision_path(cfg, pkg)), recursive = TRUE, showWarnings = FALSE)
  write_yaml_canonical(stub, decision_path(cfg, pkg),
                       header = "avior review stub - fill in and sign (PRD 6.3)")
}

in_scope_packages <- function(inventory) {
  pkgs <- Filter(function(p) isTRUE(p$in_scope), inventory$packages)
  stats::setNames(pkgs, vapply(pkgs, function(p) p$name, character(1)))
}

# Completeness validation (FR-REVIEW-3/4/5 + depth_by_risk). Returns a list
# of finding() objects; also used by check (FR-CHECK-2).
review_findings <- function(cfg, inventory = NULL, scores = NULL) {
  if (is.null(inventory)) inventory <- read_inventory(cfg)
  if (is.null(scores)) {
    # the gate must FAIL CLOSED on an uninterpretable scores.yml, not
    # crash: report the schema defect as a structured finding (FR-X-6)
    scores <- tryCatch(read_scores(cfg), avior_error = function(e) e)
    if (inherits(scores, "avior_error")) {
      return(list(finding(
        "-", "invalid_scores", conditionMessage(scores),
        fix = "re-run `avior assess` to regenerate scores.yml")))
    }
  }
  findings <- list()
  add <- function(f) findings[[length(findings) + 1L]] <<- f

  for (p in in_scope_packages(inventory)) {
    pkg <- p$name
    path <- decision_path(cfg, pkg)
    if (!file.exists(path)) {
      add(finding(pkg, "missing_decision",
                  "no decision record for an in-scope package",
                  fix = "run `avior review` to generate a stub, then fill and sign it"))
      next
    }
    d <- tryCatch(read_yaml_file(path), error = function(e) NULL)
    if (is.null(d) || !is.list(d)) {
      add(finding(pkg, "invalid_decision",
                  paste0("cannot parse ", path, " as a decision record"),
                  fix = "fix the YAML structure in the decision record (see PRD 6.3)"))
      next
    }
    if (!avior_schema_v1(d$avior)) {
      # exact version match (FR-X-6): as.integer() would truncate `1.5`
      # and coerce `true` to 1L, silently reading an unknown schema as v1
      add(finding(pkg, "invalid_decision",
                  "decision record has a missing or unsupported schema version (expected avior: 1)",
                  fix = "set `avior: 1` in the decision record"))
      next
    }
    # bind the record to its package: the filename is decisions/<pkg>.yml, so a
    # mismatched `package:` field means the file, its embedded identity and the
    # downstream traceability point at different objects (fail closed)
    if (!identical(d$package %||% "", pkg)) {
      add(finding(pkg, "package_mismatch",
                  paste0("decision file decisions/", pkg, ".yml declares package `",
                         d$package %||% "<none>", "`"),
                  fix = "make the `package:` field match the filename (and the inventory)"))
      next
    }

    sp <- scores$packages[[pkg]]
    if (is.null(sp)) {
      # fail closed: without a score there is no tier, so tier-based depth
      # rules cannot be enforced — the gate must not silently pass
      add(finding(pkg, "unscored_package",
                  "in-scope package has no entry in scores.yml",
                  fix = "run `avior assess` (or `avior assess --only <pkg>`)"))
    }
    tier <- sp$tier %||% NA_character_
    dec <- d$decision %||% ""

    if (!nzchar(dec) || !dec %in% DECISION_ENUM) {
      add(finding(pkg, "invalid_decision",
                  paste0("decision is `", dec, "` (expected ",
                         paste(DECISION_ENUM, collapse = "|"), ")"),
                  fix = "set decision to include|include_with_tests|exclude"))
    }
    if (!nzchar(trimws(d$reviewed_by %||% ""))) {
      add(finding(pkg, "unsigned", "decision has no reviewer signature",
                  fix = "set reviewed_by to the reviewer's identity"))
    }
    if (!nzchar(trimws(d$rationale %||% ""))) {
      add(finding(pkg, "empty_rationale", "decision has no rationale",
                  fix = "record why this decision is appropriate"))
    }
    if (!identical(d$version %||% "", p$version)) {
      add(finding(pkg, "stale_decision",
                  paste0("decision refers to version ", d$version %||% "<none>",
                         " but the inventory has ", p$version),
                  fix = "re-run `avior assess` and re-review the package"))
    } else if (!is.null(sp)) {
      # Even at the same package version, the risk RESULT the decision was
      # approved against can change: switching engines (PRD 7.2) or changing
      # policy weights/metrics moves score/tier. An old approval must not
      # silently stand over a newer assessment. scored_at is deliberately not
      # compared — it changes on every re-score even when the result is equal.
      snap <- if (is.list(d$score_snapshot)) d$score_snapshot else list()
      cur_engine <- trimws(paste(scores$engine$id %||% "", scores$engine$version %||% ""))
      snap_score <- suppressWarnings(round(as.numeric(snap$score %||% NA), 4))
      cur_score <- suppressWarnings(round(as.numeric(sp$score %||% NA), 4))
      stale <- !identical(snap$engine %||% "", cur_engine) ||
        !identical(snap$tier %||% "", sp$tier %||% "") ||
        !isTRUE(all.equal(snap_score, cur_score))
      if (stale) {
        add(finding(pkg, "stale_score",
                    "decision's score_snapshot no longer matches the current assessment (engine/score/tier changed; PRD 7.2)",
                    fix = "re-review the package against the current scores.yml and refresh the decision"))
      }
    }
    if (tier %in% c("medium", "high") && !identical(dec, "exclude") &&
        !nzchar(trimws(d$use_statement %||% ""))) {
      # use_statement drives targeted tests / AI drafting (FR-REVIEW-4);
      # it is meaningless for a package being removed, so excludes are exempt
      add(finding(pkg, "missing_use_statement",
                  paste0("tier is ", tier, " but use_statement is empty (FR-REVIEW-4)"),
                  fix = "declare how this project uses the package"))
    }
    tests <- unlist(d$tests)
    if (identical(dec, "include_with_tests")) {
      # A targeted test must be an actual testthat file under validation/tests/
      # (FR-TEST-1/FR-REVIEW-2). Merely "some existing file" lets avior.yml or
      # any decisions/*.yml masquerade as a test. Require the tests/ prefix,
      # a .R extension, no traversal, and existence under the validation dir.
      valid_test <- function(t) {
        rel <- sub("^validation/", "", t)
        if (grepl("..", rel, fixed = TRUE)) return(FALSE)
        if (!grepl("^tests/", rel)) return(FALSE)
        if (!grepl("\\.[Rr]$", rel)) return(FALSE)
        file.exists(file.path(cfg$paths$validation, rel))
      }
      if (length(tests) == 0 || !all(vapply(tests, valid_test, logical(1)))) {
        add(finding(pkg, "missing_tests",
                    "include_with_tests requires at least one existing testthat file under validation/tests/ (path tests/<name>.R)",
                    fix = "add targeted tests under validation/tests/ and list them as tests/<name>.R"))
      }
    }
    if (identical(tier, "high") && identical(dec, "include") &&
        identical(cfg$depth_by_risk$high, "targeted_tests_required")) {
      add(finding(pkg, "depth_requires_tests",
                  "high-risk package included without targeted tests (depth_by_risk.high)",
                  fix = "change the decision to include_with_tests and add tests, or justify exclusion"))
    }
    if (isTRUE(d$ai_assisted) && !nzchar(trimws(d$confirmed_by %||% ""))) {
      add(finding(pkg, "unconfirmed_ai",
                  "ai_assisted decision lacks a confirming human (FR-REVIEW-5)",
                  fix = "set confirmed_by to the confirming reviewer"))
    }
  }
  findings
}

avior_review <- function(root = ".") {
  cfg <- avior_config_load(root)
  inventory <- read_inventory(cfg)
  scores <- read_scores(cfg)

  stubs <- character(0)
  for (p in in_scope_packages(inventory)) {
    if (file.exists(decision_path(cfg, p$name))) next
    sp <- scores$packages[[p$name]]
    snapshot <- list(
      score = sp$score %||% NA_real_,
      tier = sp$tier %||% "unscored",
      scored_at = scores$scored_at,
      engine = paste(scores$engine$id, scores$engine$version)
    )
    write_decision_stub(cfg, p$name, p$version, snapshot)
    stubs <- c(stubs, p$name)
  }

  list(stubs_created = stubs,
       findings = review_findings(cfg, inventory, scores))
}
