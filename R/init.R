# avior init — scaffolding (FR-INIT-1/2). Idempotent: existing files are
# never overwritten. The generated avior.yml is a human-edited template
# (category (2) in the example's file taxonomy), so it carries comments;
# generated artifacts (category (3)) go through the canonical writers instead.

# The skeleton ships as an installed file (inst/templates/avior.yml): it
# carries Chinese guidance comments, and R code must stay ASCII-only for
# portability. __PROJECT_NAME__ is substituted on copy.
init_config_template <- function(project_name) {
  tpl <- system.file("templates", "avior.yml", package = "avior", mustWork = TRUE)
  txt <- readChar(tpl, file.size(tpl), useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  # split on \r?\n: a CRLF checkout of the template must not leak CR bytes
  # into the generated file (FR-X-8 mandates LF on every platform)
  lines <- strsplit(txt, "\r?\n")[[1]]
  sub("__PROJECT_NAME__", project_name, lines, fixed = TRUE)
}

avior_init <- function(root = ".", ci = NULL) {
  if (!is.null(ci)) {
    avior_abort("avior init --ci is planned for V1 (FR-INIT-3) and not implemented yet")
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

  invisible(list(created = created, skipped = skipped))
}
