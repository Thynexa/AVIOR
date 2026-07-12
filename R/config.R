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
    report = list(formats = c("html", "docx"), language = "zh")
  )
}

# Merge user config over defaults, one level of nesting at a time.
merge_config <- function(defaults, user) {
  for (key in names(user)) {
    if (is.list(defaults[[key]]) && is.list(user[[key]]) &&
        !is.null(names(defaults[[key]]))) {
      defaults[[key]] <- merge_config(defaults[[key]], user[[key]])
    } else {
      defaults[[key]] <- user[[key]]
    }
  }
  defaults
}

config_abort <- function(msg) avior_abort(msg, class = "avior_config_error")

avior_config_load <- function(root = ".") {
  path <- file.path(root, "validation", "avior.yml")
  if (!file.exists(path)) {
    config_abort(paste0("config not found: ", path, " (run `avior init` first)"))
  }
  user <- read_yaml_file(path)
  if (!is.list(user)) config_abort("avior.yml is not a YAML mapping")

  if (is.null(user$avior)) {
    config_abort("avior.yml: missing schema version field `avior` (expected: avior: 1)")
  }
  if (!identical(as.integer(user$avior), 1L)) {
    config_abort(paste0("avior.yml: unsupported schema version `", user$avior,
                        "` (this avior release reads schema 1)"))
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

  rationale <- cfg$policy$rationale
  cfg$rationale_todo <- is.null(rationale) || !nzchar(trimws(rationale)) ||
    grepl("TODO", rationale, fixed = TRUE)

  cfg$root <- normalizePath(root)
  cfg$paths <- list(validation = file.path(cfg$root, cfg$project$validation_dir))
  class(cfg) <- "avior_config"
  cfg
}
