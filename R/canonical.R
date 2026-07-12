# FR-X-8 canonical serialization. Every generated artifact must be written
# through these helpers: UTF-8 without BOM, LF line endings on every platform,
# decimal-only numbers (max 4 fractional digits, >=1 kept), UTC ISO-8601
# timestamps, and a fixed YAML/JSON/CSV style. The YAML emitter is
# deliberately custom: yaml::as.yaml output varies across package versions
# (and emits yes/no booleans), which would break the byte-identical ACs.

# -- numbers ------------------------------------------------------------------

avior_format_num <- function(x) {
  vapply(as.numeric(x), function(v) {
    if (is.na(v)) return(NA_character_)
    s <- format(round(v, 4), scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
    if (!grepl(".", s, fixed = TRUE)) s <- paste0(s, ".0")
    s
  }, character(1), USE.NAMES = FALSE)
}

# -- timestamps ---------------------------------------------------------------

avior_timestamp <- function(time = NULL) {
  if (is.null(time)) {
    sde <- Sys.getenv("SOURCE_DATE_EPOCH", unset = "")
    time <- if (nzchar(sde)) {
      as.POSIXct(as.numeric(sde), origin = "1970-01-01", tz = "UTC")
    } else {
      Sys.time()
    }
  }
  format(as.POSIXct(time, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# -- raw line writer ----------------------------------------------------------

# Convert to UTF-8 without mangling: enc2utf8() on "unknown"-encoding strings
# in a C locale escapes non-ASCII bytes to "<e9>"-style literals. Only strings
# explicitly marked latin1 need conversion; UTF-8 and unknown pass through
# byte-for-byte (useBytes = TRUE below prevents any re-encoding on write).
to_utf8 <- function(x) {
  x <- as.character(x)
  latin <- !is.na(x) & Encoding(x) == "latin1"
  x[latin] <- enc2utf8(x[latin])
  x
}

write_lines_lf <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(to_utf8(lines), con, sep = "\n", useBytes = TRUE)
  invisible(path)
}

# Locale-independent YAML reading: slurp bytes, mark as UTF-8, parse.
# yaml::read_yaml() goes through readLines() in the session locale, which
# breaks on UTF-8 content under a C locale.
read_yaml_file <- function(path) {
  txt <- readChar(path, file.size(path), useBytes = TRUE)
  Encoding(txt) <- "UTF-8"
  yaml::yaml.load(txt)
}

# -- YAML emitter -------------------------------------------------------------

# Mark a map so it is emitted inline (`{ k: v, ... }`). Flow style is only
# used where PRD 6.x fixes it per artifact (inventory package rows, scores
# engine/metrics rows, risk_tiers, ...).
yaml_flow <- function(x) structure(x, avior_yaml_flow = TRUE)

yaml_is_flow <- function(x) isTRUE(attr(x, "avior_yaml_flow", exact = TRUE))

yaml_reserved <- c("true", "false", "null", "yes", "no", "on", "off")

yaml_string <- function(s) {
  s <- to_utf8(s)
  if (grepl("^[A-Za-z_][A-Za-z0-9._-]*$", s) && !(tolower(s) %in% yaml_reserved)) {
    return(s)
  }
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub('"', '\\"', s, fixed = TRUE)
  paste0('"', s, '"')
}

yaml_scalar <- function(v) {
  if (is.null(v)) return("null")
  if (is.logical(v)) return(if (is.na(v)) "null" else if (v) "true" else "false")
  if (is.integer(v)) return(as.character(v))
  if (is.numeric(v)) {
    s <- avior_format_num(v)
    return(if (is.na(s)) "null" else s)
  }
  if (is.na(v)) return("null")
  yaml_string(v)
}

yaml_is_map <- function(x) is.list(x) && !is.null(names(x)) && any(nzchar(names(x)))

# Inline scalar sequence: `[a, b]`; empty -> `[]`.
yaml_inline_seq <- function(v) {
  if (length(v) == 0) return("[]")
  paste0("[", paste(vapply(v, yaml_scalar, character(1)), collapse = ", "), "]")
}

yaml_flow_map <- function(x) {
  if (length(x) == 0) return("{}")
  parts <- vapply(seq_along(x), function(i) {
    paste0(yaml_string(names(x)[i]), ": ", yaml_scalar(x[[i]]))
  }, character(1))
  paste0("{ ", paste(parts, collapse = ", "), " }")
}

yaml_emit <- function(x, indent = 0) {
  pad <- strrep("  ", indent)
  out <- character(0)
  if (yaml_is_map(x)) {
    for (i in seq_along(x)) {
      key <- yaml_string(names(x)[i])
      v <- x[[i]]
      if (is.null(v)) {
        out <- c(out, paste0(pad, key, ": null"))
      } else if (yaml_is_flow(v)) {
        out <- c(out, paste0(pad, key, ": ", yaml_flow_map(v)))
      } else if (is.list(v)) {
        if (length(v) == 0) {
          out <- c(out, paste0(pad, key, ":",
                               if (yaml_is_map(v)) " {}" else " []"))
        } else {
          out <- c(out, paste0(pad, key, ":"), yaml_emit(v, indent + 1))
        }
      } else if (length(v) > 1 || length(v) == 0) {
        out <- c(out, paste0(pad, key, ": ", yaml_inline_seq(v)))
      } else {
        out <- c(out, paste0(pad, key, ": ", yaml_scalar(v)))
      }
    }
  } else if (is.list(x)) {
    # sequence
    for (v in x) {
      if (yaml_is_flow(v)) {
        out <- c(out, paste0(pad, "- ", yaml_flow_map(v)))
      } else if (is.list(v)) {
        block <- yaml_emit(v, indent + 1)
        block[1] <- paste0(pad, "- ", sub("^\\s+", "", block[1]))
        out <- c(out, block)
      } else {
        out <- c(out, paste0(pad, "- ", yaml_scalar(v)))
      }
    }
  } else if (length(x) > 1) {
    for (v in x) out <- c(out, paste0(pad, "- ", yaml_scalar(v)))
  } else {
    out <- c(out, paste0(pad, yaml_scalar(x)))
  }
  out
}

write_yaml_canonical <- function(x, path, header = NULL) {
  lines <- character(0)
  if (!is.null(header)) lines <- paste0("# ", header)
  lines <- c(lines, yaml_emit(x, 0))
  write_lines_lf(lines, path)
}

# -- JSON writer --------------------------------------------------------------

write_json_canonical <- function(x, path) {
  txt <- jsonlite::toJSON(x, pretty = 2, auto_unbox = TRUE,
                          null = "null", na = "null", digits = NA)
  write_lines_lf(as.character(txt), path)
}

# -- CSV writer ---------------------------------------------------------------

csv_field <- function(v) {
  if (length(v) != 1 || is.na(v)) return("")
  s <- if (is.numeric(v) && !is.integer(v)) avior_format_num(v) else to_utf8(v)
  needs_quote <- grepl('[",\n\r]', s) || any(charToRaw(s) > as.raw(127L))
  if (needs_quote) {
    s <- gsub('"', '""', s, fixed = TRUE)
    s <- paste0('"', s, '"')
  }
  s
}

write_csv_canonical <- function(df, path) {
  header <- paste(names(df), collapse = ",")
  rows <- vapply(seq_len(nrow(df)), function(i) {
    paste(vapply(seq_along(df), function(j) csv_field(df[[j]][i]), character(1)),
          collapse = ",")
  }, character(1))
  write_lines_lf(c(header, rows), path)
}

# -- C-locale ordering (FR-X-7) ----------------------------------------------

sort_c <- function(x) sort(x, method = "radix")

order_c <- function(...) order(..., method = "radix")
