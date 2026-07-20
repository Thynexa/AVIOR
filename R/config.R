# avior.yml loading + schema validation (FR-X-1, PRD 6.2).
#
# The config file itself always lives at <root>/validation/avior.yml.
# project.validation_dir controls where the OTHER artifacts (inventory,
# scores, decisions, ...) are read/written; it defaults to "validation".

config_defaults <- function() {
  list(
    project = list(name = NULL, validation_dir = "validation"),
    scope = list(
      lockfile = "renv.lock",
      intended_for_use = "auto",
      include = character(0),
      exclude = character(0),
      custom_orgs = character(0)
    ),
    policy = list(
      engine = "riskmetric",
      weights = NULL,
      risk_tiers = list(low_max = 0.25, high_min = 0.55),
      na_action = "reweight",
      rationale = NULL
    ),
    depth_by_risk = list(
      low = "metadata_only",
      medium = "use_statement_required",
      high = "targeted_tests_required"
    ),
    # English-first delivery (issue #33): zh stays a fail-closed placeholder
    # locale until a complete translation ships
    report = list(formats = c("html", "docx"), language = "en")
  )
}

# Merge user config over defaults, one level of nesting at a time.
# A NULL user value (an empty YAML section, e.g. `scope:` with everything
# commented out) keeps the defaults; a scalar where a mapping is expected
# is a schema error, not a silent overwrite.
merge_config <- function(defaults, user, path = character(0)) {
  for (key in names(user)) {
    uv <- user[[key]]
    if (is.null(uv)) next
    dv <- defaults[[key]]
    if (is.list(dv) && !is.null(names(dv)) && any(nzchar(names(dv)))) {
      if (!is.list(uv)) {
        config_abort(paste0("avior.yml: `", paste(c(path, key), collapse = "."),
                            "` must be a mapping, got a scalar"))
      }
      defaults[[key]] <- merge_config(dv, uv, c(path, key))
    } else {
      defaults[[key]] <- uv
    }
  }
  defaults
}

config_abort <- function(msg) avior_abort(msg, class = "avior_config_error")

# Config discovery (FR-X-1): the default home is <root>/validation/avior.yml.
# A renamed validation dir is supported when it is unambiguous: exactly one
# <root>/<dir>/avior.yml exists and its project.validation_dir names that dir.
find_config <- function(root) {
  default <- file.path(root, "validation", "avior.yml")
  if (file.exists(default)) return(default)
  candidates <- Sys.glob(file.path(root, "*", "avior.yml"))
  if (length(candidates) == 1) return(candidates[1])
  if (length(candidates) > 1) {
    config_abort(paste0("multiple avior.yml candidates found under ", root, ": ",
                        paste(candidates, collapse = ", "),
                        " (keep exactly one validation dir)"))
  }
  config_abort(paste0("config not found: ", default, " (run `avior init` first)"))
}

avior_config_load <- function(root = ".") {
  path <- find_config(root)
  user <- tryCatch(
    read_yaml_file(path),
    error = function(e) {
      config_abort(paste0("cannot parse ", path, ": ", conditionMessage(e)))
    }
  )
  if (!is.list(user)) config_abort("avior.yml is not a YAML mapping")

  if (is.null(user$avior)) {
    config_abort("avior.yml: missing schema version field `avior` (expected: avior: 1)")
  }
  # Exact version match (FR-X-6): as.integer() would truncate `1.5`/`1.9` and
  # coerce `true` to 1L, silently accepting a future/invalid schema as v1.
  ver <- user$avior
  if (!avior_schema_v1(ver)) {
    config_abort(paste0("avior.yml: unsupported schema version `",
                        paste(format(ver), collapse = ", "),
                        "` (this avior release reads schema exactly 1)"))
  }

  cfg <- merge_config(config_defaults(), user)

  # normalize scalars-from-yaml into character vectors where lists are allowed
  for (f in c("include", "exclude", "custom_orgs")) {
    cfg$scope[[f]] <- as.character(unlist(cfg$scope[[f]]))
  }

  w <- cfg$policy$weights
  if (is.null(w) || length(w) == 0) {
    config_abort("avior.yml: policy.weights must name at least one metric (PRD FR-ASSESS-1)")
  }
  wv <- unlist(w)
  if (!is.numeric(wv) || anyNA(wv) || any(wv < 0) ||
      is.null(names(w)) || any(!nzchar(names(w)))) {
    config_abort("avior.yml: policy.weights must be named non-negative numbers")
  }
  if (sum(wv) <= 0) {
    config_abort("avior.yml: policy.weights must have a positive total weight")
  }
  cfg$policy$weights <- as.list(stats::setNames(as.numeric(wv), names(w)))

  rt <- cfg$policy$risk_tiers
  ok_tiers <- is.numeric(rt$low_max) && is.numeric(rt$high_min) &&
    rt$low_max > 0 && rt$high_min < 1 && rt$low_max < rt$high_min
  if (!ok_tiers) {
    config_abort("avior.yml: policy.risk_tiers requires 0 < low_max < high_min < 1")
  }

  if (!cfg$policy$na_action %in% c("reweight", "zero", "fail")) {
    config_abort(paste0("avior.yml: policy.na_action must be reweight|zero|fail, got `",
                        cfg$policy$na_action, "`"))
  }

  if (!cfg$scope$intended_for_use %in% c("auto", "explicit")) {
    config_abort(paste0("avior.yml: scope.intended_for_use must be auto|explicit, got `",
                        cfg$scope$intended_for_use, "`"))
  }

  actual_dir <- basename(dirname(path))
  if (!identical(cfg$project$validation_dir, actual_dir)) {
    config_abort(paste0("avior.yml: project.validation_dir (`",
                        cfg$project$validation_dir,
                        "`) does not match the directory containing avior.yml (`",
                        actual_dir, "`)"))
  }

  rationale <- cfg$policy$rationale
  cfg$rationale_todo <- is.null(rationale) || !nzchar(trimws(rationale)) ||
    grepl("TODO", rationale, fixed = TRUE)

  cfg$root <- normalizePath(root)
  cfg$paths <- list(validation = file.path(cfg$root, cfg$project$validation_dir))
  class(cfg) <- "avior_config"
  cfg
}
