# avior init — scaffolding (FR-INIT-1/2) and optional CI workflow
# generation (FR-INIT-3). Idempotent: existing files are never
# overwritten. The generated avior.yml is a human-edited template
# (category (2) in the example's file taxonomy), so it carries comments;
# generated artifacts (category (3)) go through the canonical writers instead.

# The skeleton ships as an installed file (inst/templates/avior.yml): it
# carries Chinese guidance comments, and R code must stay ASCII-only for
# portability. __PROJECT_NAME__ is substituted on copy.
init_template_lines <- function(name) {
  tpl <- system.file("templates", name, package = "avior", mustWork = TRUE)
  txt <- readChar(tpl, file.size(tpl), useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  # split on \r?\n: a CRLF checkout of the template must not leak CR bytes
  # into the generated file (FR-X-8 mandates LF on every platform)
  strsplit(txt, "\r?\n")[[1]]
}

init_config_template <- function(project_name) {
  sub("__PROJECT_NAME__", project_name, init_template_lines("avior.yml"),
      fixed = TRUE)
}

# FR-INIT-3: static CI workflow templates keyed by provider. The target
# path is fixed by the provider's convention; content is deterministic
# (no timestamps) so a re-run against an unchanged template is a no-op.
CI_PROVIDERS <- list(
  github = list(template = "ci-github.yml",
                path = file.path(".github", "workflows", "avior.yml")),
  gitlab = list(template = "ci-gitlab.yml", path = ".gitlab-ci.yml")
)

avior_init <- function(root = ".", ci = NULL) {
  if (!is.null(ci) &&
      !(is.character(ci) && length(ci) == 1 && ci %in% names(CI_PROVIDERS))) {
    avior_abort(paste0(
      "unsupported --ci `", paste(format(ci), collapse = ", "),
      "` (expected ", paste(names(CI_PROVIDERS), collapse = "|"), ")"))
  }
  vdir <- file.path(root, "validation")
  created <- character(0)
  skipped <- character(0)

  for (d in c(vdir, file.path(vdir, "decisions"), file.path(vdir, "tests"),
              file.path(vdir, "evidence"), file.path(vdir, ".cache"))) {
    if (!dir.exists(d)) {
      dir.create(d, recursive = TRUE)
      created <- c(created, paste0(d, "/"))
    }
  }

  write_if_absent <- function(path, lines) {
    if (file.exists(path)) {
      skipped <<- c(skipped, path)
    } else {
      write_lines_lf(lines, path)
      created <<- c(created, path)
    }
  }

  project_name <- basename(normalizePath(root))
  write_if_absent(file.path(vdir, "avior.yml"), init_config_template(project_name))
  write_if_absent(file.path(vdir, ".gitignore"), c(".cache/", "evidence/*.zip"))

  if (!is.null(ci)) {
    provider <- CI_PROVIDERS[[ci]]
    target <- file.path(root, provider$path)
    d <- dirname(target)
    if (!dir.exists(d)) {
      dir.create(d, recursive = TRUE)
      created <- c(created, paste0(d, "/"))
    }
    # write_if_absent: an existing workflow is the user's (possibly edited)
    # file and is never overwritten (FR-INIT-3), only reported as kept
    write_if_absent(target, init_template_lines(provider$template))
  }

  invisible(list(created = created, skipped = skipped))
}
