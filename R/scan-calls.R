# Static intended-for-use detection (FR-SCAN-3). Token-based on
# getParseData(): SYMBOL_PACKAGE catches pkg::/pkg::: usage; attach-style
# calls (library/require/requireNamespace/loadNamespace) are resolved to
# their first argument when it is a literal string or a bare symbol.
# `character.only = TRUE` with a bare symbol means the symbol is a variable,
# not a package name -> skipped (dynamic call, FR-SCAN risk table).

ATTACH_FUNS <- c("library", "require", "requireNamespace", "loadNamespace")

empty_calls <- function() {
  data.frame(package = character(0), file = character(0), line = integer(0),
             stringsAsFactors = FALSE)
}

scan_file_calls <- function(path, rel) {
  exprs <- parse(path, keep.source = TRUE)
  pd <- utils::getParseData(exprs)
  if (is.null(pd) || nrow(pd) == 0) return(empty_calls())

  rows <- list()

  sp <- pd[pd$token == "SYMBOL_PACKAGE", , drop = FALSE]
  for (i in seq_len(nrow(sp))) {
    rows[[length(rows) + 1L]] <-
      list(package = sp$text[i], line = as.integer(sp$line1[i]), col = sp$col1[i])
  }

  calls <- pd[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text %in% ATTACH_FUNS, , drop = FALSE]
  for (i in seq_len(nrow(calls))) {
    fn_expr <- calls$parent[i]
    call_id <- pd$parent[pd$id == fn_expr]
    kids <- pd[pd$parent == call_id, , drop = FALSE]
    kids <- kids[order(kids$line1, kids$col1), , drop = FALSE]

    # Separate positional from named arguments: an expr immediately after a
    # SYMBOL_SUB/EQ_SUB pair belongs to that name. The package may arrive
    # positionally (library(x)) or as `package =` (requireNamespace(quietly
    # = TRUE, package = "x")); `library(help = x)` attaches nothing.
    positional <- integer(0)
    named <- character(0)
    named_ids <- integer(0)
    pending <- NA_character_
    for (k in seq_len(nrow(kids))) {
      tokk <- kids$token[k]
      if (tokk == "SYMBOL_SUB") {
        pending <- kids$text[k]
      } else if (tokk == "expr" && kids$id[k] != fn_expr) {
        if (is.na(pending)) {
          positional <- c(positional, kids$id[k])
        } else {
          named <- c(named, pending)
          named_ids <- c(named_ids, kids$id[k])
          pending <- NA_character_
        }
      }
    }
    target <- if (length(positional) > 0) {
      positional[1]
    } else if ("package" %in% named) {
      named_ids[match("package", named)]
    } else {
      NA_integer_
    }
    if (is.na(target)) next

    term <- pd[pd$parent == target, , drop = FALSE]
    tok <- term[term$token %in% c("STR_CONST", "SYMBOL"), , drop = FALSE]
    if (nrow(tok) != 1) next
    # A bare symbol is a static package name unless character.only forces the
    # symbol to be read as a variable. Only skip when character.only is TRUE
    # or a non-literal we cannot resolve; `character.only = FALSE` (or absent)
    # keeps the bare name — library(pkg, character.only = FALSE) is static.
    if (tok$token == "SYMBOL") {
      co_idx <- match("character.only", named)
      if (!is.na(co_idx)) {
        co_term <- pd[pd$parent == named_ids[co_idx], , drop = FALSE]
        # Only the reserved literal FALSE (a NUM_CONST) is a safe static false.
        # `F`/`T` are ordinary rebindable variables (SYMBOL), so without data-
        # flow analysis their value is not statically determinable -> skip.
        co_lit <- co_term$text[co_term$token == "NUM_CONST"]
        literal_false <- length(co_lit) == 1 && identical(co_lit, "FALSE")
        if (!literal_false) next
      }
    }
    pkg <- tok$text
    if (tok$token == "STR_CONST") pkg <- gsub("^['\"]|['\"]$", "", pkg)
    if (!nzchar(pkg)) next
    rows[[length(rows) + 1L]] <-
      list(package = pkg, line = as.integer(calls$line1[i]), col = calls$col1[i])
  }

  if (length(rows) == 0) return(empty_calls())
  df <- data.frame(
    package = vapply(rows, `[[`, character(1), "package"),
    file = rel,
    line = vapply(rows, `[[`, integer(1), "line"),
    col = vapply(rows, function(r) as.integer(r$col), integer(1)),
    stringsAsFactors = FALSE
  )
  df <- df[order(df$line, df$col), c("package", "file", "line"), drop = FALSE]
  rownames(df) <- NULL
  df
}

scan_direct_calls <- function(root, exclude_dirs = c("validation", "renv", "packrat")) {
  files <- list.files(root, pattern = "\\.[Rr]$", recursive = TRUE)
  keep <- !vapply(files, function(f) {
    any(vapply(exclude_dirs, function(d) startsWith(f, paste0(d, "/")), logical(1)))
  }, logical(1))
  files <- sort_c(files[keep])

  skipped <- character(0)
  per_file <- list()
  for (f in files) {
    df <- tryCatch(
      scan_file_calls(file.path(root, f), f),
      error = function(e) {
        warning(paste0("avior scan: cannot parse ", f, " (", conditionMessage(e),
                       "); file skipped, review scope manually"), call. = FALSE)
        skipped <<- c(skipped, f)
        NULL
      }
    )
    if (!is.null(df)) per_file[[length(per_file) + 1L]] <- df
  }

  out <- if (length(per_file)) do.call(rbind, per_file) else empty_calls()
  out <- out[!duplicated(out$package), , drop = FALSE]
  rownames(out) <- NULL
  attr(out, "skipped") <- skipped
  out
}
