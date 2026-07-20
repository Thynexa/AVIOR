# avior bundle — the evidence compiler (FR-BUNDLE-1,2,4..8). Snapshots the
# validated project state into an immutable validation/evidence/bundle-<UTC>/
# directory: byte-copies of the inputs, traceability.csv (PRD 6.5),
# environment.json + session-info.txt (FR-BUNDLE-5), BUNDLE.yml metadata,
# and a path-sorted MANIFEST.sha256 covering every file except itself.
#
# Report rendering happens behind the render_report() boundary: the
# compiler passes one bundle model built EXCLUSIVELY from the snapshot
# copies (so report facts reconcile with the snapshots by construction)
# and never contains narrative strings itself.

bundle_gate <- function(root, force) {
  gate <- avior_check(root)
  if (identical(gate$status, "fail") && !isTRUE(force)) {
    return(list(proceed = FALSE, gate = gate))
  }
  list(proceed = TRUE, gate = gate)
}

# Byte-copies of the compilation inputs (FR-BUNDLE-2). The inventory is
# non-negotiable — without it the bundle has no package facts even under
# --force; scores/test-results are snapshot when present.
bundle_snapshot <- function(cfg, staging) {
  snap <- file.path(staging, "snapshot")
  dir.create(snap, recursive = TRUE)
  vdir <- cfg$paths$validation

  inv <- file.path(vdir, "inventory.yml")
  if (!file.exists(inv)) {
    avior_abort(paste0("cannot compile a bundle without an inventory: ", inv,
                       " (run `avior scan` first)"))
  }
  copy_in <- function(name) {
    src <- file.path(vdir, name)
    if (file.exists(src)) {
      stopifnot(file.copy(src, file.path(snap, name)))
      TRUE
    } else {
      FALSE
    }
  }
  copy_in("avior.yml")
  copy_in("inventory.yml")
  copy_in("scores.yml")
  copy_in("test-results.yml")
  dec_dir <- file.path(vdir, "decisions")
  decs <- sort_c(list.files(dec_dir, pattern = "\\.yml$"))
  if (length(decs) > 0) {
    dir.create(file.path(snap, "decisions"))
    for (f in decs) {
      stopifnot(file.copy(file.path(dec_dir, f),
                          file.path(snap, "decisions", f)))
    }
  }
  snap
}

# Row-level disposition for the traceability matrix (PRD 6.5): in-scope
# rows carry the FR-REVIEW-2 decision enum from their decision record;
# transitive rows the fixed status `version_managed`; out-of-scope direct
# rows `excluded` (scope.exclude) or `exempt` (base/recommended policy
# default) — with blank score/tier/decision-file fields, like transitive.
trace_row <- function(p, decisions, scores, tests) {
  pkg <- p$name
  d <- decisions[[pkg]]
  sp <- if (!is.null(scores)) scores$packages[[pkg]] else NULL
  in_scope <- isTRUE(p$in_scope)
  # every cell must be a length-1 value: a decision field that is absent
  # or malformed (a stub without reviewed_by, hand-edited YAML) becomes
  # NA, never NULL — NULL cells would collapse the data.frame columns
  cell <- function(v) {
    if (is.character(v) && length(v) == 1L && !is.na(v)) v else NA_character_
  }

  decision <- if (in_scope) {
    if (!is.null(d)) d$decision else NA_character_
  } else if (identical(p$role, "transitive")) {
    "version_managed"
  } else if (identical(p$override_source %||% "", "avior.yml scope.exclude")) {
    "excluded"
  } else {
    "exempt"
  }

  test_rows <- Filter(function(r) identical(r$package, pkg),
                      if (!is.null(tests)) tests$results else list())
  # shared row rule (test_row_passing): "pass" only when EVERY recorded
  # row for the package is passing evidence — one green file must not
  # mask a sibling all-skipped/zero-test file in the audit matrix
  test_status <- if (length(test_rows) == 0) {
    NA_character_
  } else if (all(vapply(test_rows, test_row_passing, logical(1)))) {
    "pass"
  } else {
    "fail"
  }
  test_files <- if (!is.null(d) && length(d$tests) > 0) {
    paste(unlist(d$tests), collapse = ";")
  } else {
    NA_character_
  }

  list(
    package = pkg,
    version = p$version,
    classification = p$classification,
    role = p$role,
    score = if (in_scope && !is.null(sp) && is.numeric(sp$score) &&
                  length(sp$score) == 1L) {
      as.numeric(sp$score)
    } else {
      NA_real_
    },
    tier = if (in_scope && !is.null(sp)) cell(sp$tier) else NA_character_,
    decision = decision,
    use_statement_ref = if (in_scope && !is.null(d)) {
      paste0("decisions/", pkg, ".yml#use_statement")
    } else {
      NA_character_
    },
    decision_file = if (in_scope && !is.null(d)) {
      paste0("decisions/", pkg, ".yml")
    } else {
      NA_character_
    },
    reviewed_by = if (in_scope && !is.null(d)) cell(d$reviewed_by) else
      NA_character_,
    decision_date = if (in_scope && !is.null(d)) cell(d$date) else
      NA_character_,
    test_files = test_files,
    test_status = test_status,
    notes = p$note %||% NA_character_
  )
}

TRACE_COLUMNS <- c("package", "version", "classification", "role", "score",
                   "tier", "decision", "use_statement_ref", "decision_file",
                   "reviewed_by", "decision_date", "test_files",
                   "test_status", "notes")

build_trace <- function(inventory, decisions, scores, tests) {
  rows <- lapply(inventory$packages, trace_row,
                 decisions = decisions, scores = scores, tests = tests)
  if (length(rows) == 0) {
    df <- as.data.frame(stats::setNames(
      lapply(TRACE_COLUMNS, function(col) {
        if (identical(col, "score")) numeric(0) else character(0)
      }), TRACE_COLUMNS), stringsAsFactors = FALSE)
    return(df)
  }
  cols <- names(rows[[1]])
  df <- as.data.frame(
    stats::setNames(lapply(cols, function(col) {
      vals <- lapply(rows, `[[`, col)
      if (identical(col, "score")) as.numeric(unlist(vals)) else
        as.character(unlist(vals))
    }), cols),
    stringsAsFactors = FALSE)
  df[order_c(df$package), , drop = FALSE]
}

# The single renderer boundary consumed by the report layer. Everything the
# report may state lives in `model`, which is built from the snapshot
# copies only. Returns the relative filenames it wrote into the staging
# dir; narrative strings live entirely behind this boundary.
build_bundle_model <- function(cfg, snap, meta, integrity) {
  # Forced compilation must survive inputs that `check` already reported
  # as findings (invalid_test_results, unparseable decisions): the bundle
  # then carries the snapshot bytes plus the disclosure, and the model
  # treats the artifact as unavailable instead of crashing (FR-BUNDLE-6).
  # The inventory stays strict — avior_check itself cannot run without it,
  # so no forced path reaches this point with an unreadable inventory.
  read_tolerant <- function(path) {
    x <- tryCatch(read_yaml_file(path), error = function(e) NULL)
    if (is.list(x)) x else NULL
  }
  read_opt <- function(name) {
    p <- file.path(snap, name)
    if (file.exists(p)) read_tolerant(p) else NULL
  }
  inventory <- read_yaml_file(file.path(snap, "inventory.yml"))
  scores <- read_opt("scores.yml")
  tests <- read_opt("test-results.yml")
  if (!is.null(tests) && !valid_test_results(tests)) tests <- NULL
  policy <- read_yaml_file(file.path(snap, "avior.yml"))
  # the report states EFFECTIVE thresholds: a policy file that omits
  # risk_tiers runs on the validated defaults, so the model carries the
  # merged values (cfg is loaded from the same file the snapshot copies)
  policy$policy$risk_tiers <- cfg$policy$risk_tiers
  dec_files <- sort_c(list.files(file.path(snap, "decisions"),
                                 pattern = "\\.yml$"))
  decisions <- stats::setNames(
    lapply(dec_files, function(f) {
      read_tolerant(file.path(snap, "decisions", f))
    }),
    sub("\\.yml$", "", dec_files))
  # keep only decisions satisfying the reader's minimal schema: parseable
  # YAML that is not a decision record (`foo: bar`) is the same
  # invalid_decision gate failure --force must survive, so it is treated
  # as unavailable exactly like an unparseable file
  scalar_text <- function(v) {
    is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)
  }
  usable <- vapply(names(decisions), function(pkg) {
    d <- decisions[[pkg]]
    !is.null(d) && identical(d$package %||% "", pkg) &&
      scalar_text(d$decision)
  }, logical(1))
  decisions <- decisions[usable]

  # signed = a decision that would satisfy the `unsigned` review rule
  # (non-empty reviewed_by), NOT merely a decision file on disk: a --force
  # bundle disclosing `unsigned` findings must not simultaneously claim
  # every decision is signed
  signed <- sum(vapply(decisions, function(d) {
    nzchar(trimws(d$reviewed_by %||% ""))
  }, logical(1)))

  counts <- list(
    packages_total = as.integer(inventory$summary$total),
    assessed = if (!is.null(scores)) length(scores$packages) else 0L,
    decisions_signed = as.integer(signed),
    tests_run = if (!is.null(tests)) length(tests$results) else 0L
  )

  list(
    meta = meta,
    integrity = integrity,
    policy = policy,
    inventory = inventory,
    scores = scores,
    decisions = decisions,
    tests = tests,
    trace = build_trace(inventory, decisions, scores, tests),
    counts = counts
  )
}

write_bundle_yml <- function(model, path) {
  doc <- list(
    avior = 1L,
    bundle_id = model$meta$bundle_id,
    generated_at = model$meta$generated_at,
    generated_by = yaml_flow(list(
      avior_version = model$meta$avior_version,
      engine = model$meta$engine_label,
      r_version = model$meta$r_version)),
    project = list(
      name = model$meta$project_name,
      lockfile_sha256 = model$meta$lockfile_sha256,
      policy_sha256 = model$meta$policy_sha256),
    # generation-time self-attestation, NOT a trust root (PRD 5.8)
    integrity_check = model$integrity$check
  )
  if (isTRUE(model$integrity$forced)) {
    # machine-readable --force disclosure (FR-BUNDLE-6): consumers and the
    # report cover page key off these fields, not off prose
    doc$forced <- TRUE
    doc$check_findings <- as.integer(model$integrity$finding_count)
    doc$check_finding_types <- yaml_seq(model$integrity$finding_types)
  }
  doc$counts <- yaml_flow(model$counts)
  write_yaml_canonical(doc, path)
}

write_manifest <- function(staging) {
  files <- sort_c(list.files(staging, recursive = TRUE, all.files = TRUE,
                             no.. = TRUE))
  files <- setdiff(gsub("\\", "/", files, fixed = TRUE), MANIFEST_NAME)
  lines <- vapply(files, function(p) {
    paste0(sha256_file(file.path(staging, p)), "  ", p)
  }, character(1), USE.NAMES = FALSE)
  write_lines_lf(lines, file.path(staging, MANIFEST_NAME))
}

avior_bundle <- function(root = ".", force = FALSE, zip = FALSE) {
  cfg <- avior_config_load(root)

  # fail closed BEFORE any write: an unavailable report language/format
  # must never leave a partial bundle behind (issue #33)
  report_config_validate(cfg$report)

  gate <- bundle_gate(root, force)
  if (!gate$proceed) {
    return(list(status = "fail",
                findings = gate$gate$findings,
                message = paste0("check failed with ",
                                 length(gate$gate$findings),
                                 " finding(s); fix them or pass --force to ",
                                 "compile with an explicit disclosure")))
  }
  forced <- identical(gate$gate$status, "fail")
  integrity <- list(
    check = if (forced) "failed" else "passed",
    forced = forced,
    finding_count = length(gate$gate$findings),
    finding_types = sort_c(unique(vapply(gate$gate$findings,
                                         function(f) f$type, character(1))))
  )

  generated_at <- avior_timestamp()
  bundle_id <- paste0("bundle-", gsub("[-:]", "", generated_at))
  evidence <- file.path(cfg$paths$validation, "evidence")
  if (!dir.exists(evidence)) dir.create(evidence, recursive = TRUE)
  final <- file.path(evidence, bundle_id)
  if (dir.exists(final)) {
    avior_abort(paste0(
      "bundle already exists: ", final, " -- bundles are immutable and ",
      "never overwritten (FR-BUNDLE-1); retry for a fresh timestamp"))
  }
  staging <- file.path(evidence, paste0(".staging-", bundle_id))
  if (dir.exists(staging)) {
    avior_abort(paste0("stale staging directory in the way: ", staging,
                       " (remove it and retry)"))
  }
  dir.create(staging, recursive = TRUE)
  staged <- TRUE
  on.exit(if (staged) unlink(staging, recursive = TRUE, force = TRUE),
          add = TRUE)

  snap <- bundle_snapshot(cfg, staging)

  session <- capture_session()
  inventory <- read_yaml_file(file.path(snap, "inventory.yml"))
  scores <- if (file.exists(file.path(snap, "scores.yml"))) {
    # tolerate what check already reported as a finding (forced compiles)
    tryCatch({
      s <- read_yaml_file(file.path(snap, "scores.yml"))
      if (is.list(s)) s else NULL
    }, error = function(e) NULL)
  } else {
    NULL
  }
  meta <- list(
    bundle_id = bundle_id,
    generated_at = generated_at,
    avior_version = avior_version(),
    engine_label = if (!is.null(scores) && !is.null(scores$engine$id)) {
      trimws(paste(scores$engine$id, scores$engine$version %||% ""))
    } else {
      cfg$policy$engine
    },
    r_version = session$r_version,
    platform = session$platform,
    project_name = cfg$project$name %||% basename(cfg$root),
    lockfile_sha256 = inventory$lockfile$sha256,
    policy_sha256 = sha256_file(file.path(snap, "avior.yml"))
  )

  model <- build_bundle_model(cfg, snap, meta, integrity)

  s <- inventory$summary
  model$environment <- capture_environment(
    session, generated_at, inventory, scores, cfg,
    dep_src_file = tryCatch(
      resolve_dep_source(cfg$root, cfg$scope$lockfile)$file,
      avior_error = function(e) ""),
    summary_counts = list(
      total = as.integer(s$total),
      in_scope_assessed = as.integer(s$in_scope_assessed),
      recommended_exempt = as.integer(s$recommended_exempt),
      force_included = as.integer(s$force_included),
      transitive = as.integer(s$transitive)))

  write_csv_canonical(model$trace, file.path(staging, "traceability.csv"))
  write_json_canonical(model$environment,
                       file.path(staging, "environment.json"))
  write_lines_lf(strsplit(session$session_text, "\n", fixed = TRUE)[[1]],
                 file.path(staging, "session-info.txt"))

  report_files <- render_report(model, cfg$report, staging)

  write_bundle_yml(model, file.path(staging, "BUNDLE.yml"))
  write_manifest(staging)

  renamed <- tryCatch(suppressWarnings(file.rename(staging, final)),
                      error = function(e) FALSE)
  if (!isTRUE(renamed)) {
    avior_abort(paste0(
      "could not finalize bundle at ", final,
      " (a concurrent bundle with the same timestamp? bundles are never ",
      "overwritten, FR-BUNDLE-1)"))
  }
  staged <- FALSE

  zip_rel <- NULL
  if (isTRUE(zip)) {
    # transport artifact, not the archival form (FR-BUNDLE-1): gitignored
    # by `avior init`, deterministically rebuildable under
    # SOURCE_DATE_EPOCH, safe to delete and regenerate
    zip_path <- file.path(evidence, paste0(bundle_id, ".zip"))
    inner <- list.files(final, recursive = TRUE, all.files = TRUE, no.. = TRUE)
    zip_write(zip_path, evidence,
              files = file.path(bundle_id, gsub("\\", "/", inner, fixed = TRUE)))
    zip_rel <- file.path(cfg$project$validation_dir, "evidence",
                         paste0(bundle_id, ".zip"))
  }

  list(
    status = "ok",
    bundle_id = bundle_id,
    path = file.path(cfg$project$validation_dir, "evidence", bundle_id),
    integrity_check = integrity$check,
    forced = forced,
    files = length(list.files(final, recursive = TRUE, all.files = TRUE,
                              no.. = TRUE)),
    report_files = report_files,
    counts = model$counts,
    zip = zip_rel
  )
}
