# avior review — decision records (FR-REVIEW-1..5). Stubs for in-scope
# packages without a decision; completeness validation shared with check.

DECISION_ENUM <- c("include", "include_with_tests", "exclude")

read_scores <- function(cfg) {
  path <- file.path(cfg$paths$validation, "scores.yml")
  if (!file.exists(path)) {
    avior_abort(paste0("scores not found: ", path, " (run `avior assess` first)"))
  }
  read_yaml_file(path)
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
  if (is.null(scores)) scores <- read_scores(cfg)
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
      # tests must live under the validation dir ("tests/..." or
      # "validation/tests/..." spellings); no path traversal
      existing <- vapply(tests, function(t) {
        if (grepl("..", t, fixed = TRUE)) return(FALSE)
        file.exists(file.path(cfg$paths$validation, sub("^validation/", "", t)))
      }, logical(1))
      if (length(tests) == 0 || !all(existing)) {
        add(finding(pkg, "missing_tests",
                    "include_with_tests requires at least one existing test file under the validation dir",
                    fix = "add targeted tests under validation/tests/ and list them"))
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
