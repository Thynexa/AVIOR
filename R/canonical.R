# FR-X-8 canonical serialization. Every generated artifact must be written
# through these helpers: UTF-8 without BOM, LF line endings on every platform,
# decimal-only numbers (max 4 fractional digits, >=1 kept), UTC ISO-8601
# timestamps, and a fixed YAML/JSON/CSV style. The YAML emitter is
# deliberately custom: yaml::as.yaml output varies across package versions
# (and emits yes/no booleans), which would break the byte-identical ACs.

# -- numbers ------------------------------------------------------------------

avior_format_num <- function(x) {
  vapply(as.numeric(x), function(v) {
    # is.finite() rejects NA, NaN, Inf and -Inf together -> NA_character_,
    # which every writer renders as null. JSON/YAML/CSV have no decimal form
    # for non-finite values (avior_format_num(Inf) would be "Inf.0", i.e.
    # invalid JSON), so they must never reach the serialized artifact.
    if (!is.finite(v)) return(NA_character_)
    # digits = 15: format()'s default of 7 significant digits would corrupt
    # values with a large integer part (123456.7891 -> "123456.8")
    s <- format(round(v, 4), scientific = FALSE, trim = TRUE,
                drop0trailing = TRUE, digits = 15)
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
  tmp <- tempfile(".avior-write-", tmpdir = dirname(path))
  con <- file(tmp, open = "wb")
  closed <- FALSE
  on.exit({
    if (!closed) close(con)
    if (file.exists(tmp)) unlink(tmp)
  }, add = TRUE)
  writeLines(to_utf8(lines), con, sep = "\n", useBytes = TRUE)
  close(con)
  closed <- TRUE
  if (!suppressWarnings(file.rename(tmp, path))) {
    avior_abort(paste0("could not atomically replace artifact: ", path))
  }
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

# Mark a vector so it is always emitted as an inline sequence (`[a]`), even
# at length 1 where R cannot distinguish a scalar from a 1-element vector
# (needed for e.g. the `tests:` list in decision records).
yaml_seq <- function(x) structure(x, avior_yaml_seq = TRUE)

yaml_is_seq <- function(x) isTRUE(attr(x, "avior_yaml_seq", exact = TRUE))

# YAML 1.1 booleans, including the single-letter y/n forms.
yaml_reserved <- c("true", "false", "null", "yes", "no", "on", "off", "y", "n")

yaml_string <- function(s) {
  s <- to_utf8(s)
  if (grepl("^[A-Za-z_][A-Za-z0-9._-]*$", s) && !(tolower(s) %in% yaml_reserved)) {
    return(s)
  }
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub('"', '\\"', s, fixed = TRUE)
  s <- gsub("\n", "\\n", s, fixed = TRUE)
  s <- gsub("\r", "\\r", s, fixed = TRUE)
  s <- gsub("\t", "\\t", s, fixed = TRUE)
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
      } else if (yaml_is_seq(v) && !is.list(v)) {
        out <- c(out, paste0(pad, key, ": ", yaml_inline_seq(v)))
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

# Custom recursive JSON emitter. jsonlite cannot be trusted for the number
# tokens: it chooses decimal vs scientific on its own (`1e20`->`1e+20`,
# `1234567.89`->`1.235e+06`) and drops the FR-X-8-mandated trailing `.0` from
# whole-number doubles — and a post-serialization text substitution can
# corrupt any user string that happens to look like the substitution pattern.
# So numbers are formatted directly through avior_format_num and structure is
# built here; only per-scalar string ESCAPING is delegated to jsonlite (one
# value at a time, so it can never touch another field). Result: no
# scientific notation, `.0` preserved, and no string/number collision.

# Escape a JSON string by hand: jsonlite mangles non-ASCII into literal
# "<e4>"-style tokens under a C locale, the same reason the YAML emitter is
# custom. UTF-8 bytes are preserved as-is (written via useBytes); only the
# JSON-significant ASCII characters are escaped.
JSON_ESCAPES <- c("\\" = "\\\\", '"' = '\\"', "\b" = "\\b", "\f" = "\\f",
                  "\n" = "\\n", "\r" = "\\r", "\t" = "\\t")

json_escape_string <- function(s) {
  s <- to_utf8(s)
  for (ch in names(JSON_ESCAPES)) s <- gsub(ch, JSON_ESCAPES[[ch]], s, fixed = TRUE)
  # remaining C0 control chars (rare in validation data) -> \u00XX
  if (grepl("[\001-\037]", s, useBytes = TRUE)) {
    for (cc in c(1:7, 11L, 14:31)) {
      s <- gsub(rawToChar(as.raw(cc)), sprintf("\\u%04x", cc), s,
                fixed = TRUE, useBytes = TRUE)
    }
  }
  paste0('"', s, '"')
}

json_scalar <- function(v) {
  if (is.null(v)) return("null")
  if (length(v) == 0) return("[]")
  if (is.logical(v)) return(if (is.na(v)) "null" else if (v) "true" else "false")
  if (is.integer(v)) return(if (is.na(v)) "null" else as.character(v))
  if (is.numeric(v)) {
    s <- avior_format_num(v)
    return(if (is.na(s)) "null" else s)
  }
  if (is.na(v)) return("null")
  json_escape_string(v)
}

json_emit <- function(x, indent = 0) {
  pad <- strrep("  ", indent)
  pad1 <- strrep("  ", indent + 1)
  if (is.null(x)) return("null")
  if (is.list(x)) {
    if (length(x) == 0) return("[]")
    if (!is.null(names(x)) && all(nzchar(names(x)))) {          # object
      items <- vapply(seq_along(x), function(i) {
        paste0(pad1, json_escape_string(names(x)[i]), ": ", json_emit(x[[i]], indent + 1))
      }, character(1))
      return(paste0("{\n", paste(items, collapse = ",\n"), "\n", pad, "}"))
    }
    items <- vapply(x, function(v) paste0(pad1, json_emit(v, indent + 1)), character(1))  # array
    return(paste0("[\n", paste(items, collapse = ",\n"), "\n", pad, "]"))
  }
  if (length(x) <= 1) return(json_scalar(x))
  items <- vapply(x, json_scalar, character(1))                 # atomic vector -> array
  paste0("[\n", paste0(pad1, items, collapse = ",\n"), "\n", pad, "]")
}

write_json_canonical <- function(x, path) {
  write_lines_lf(json_emit(x, 0), path)
}

# -- CSV writer ---------------------------------------------------------------

csv_field <- function(v) {
  if (length(v) != 1 || is.na(v)) return("")
  s <- if (is.numeric(v) && !is.integer(v)) avior_format_num(v) else to_utf8(v)
  if (is.na(s)) return("")   # non-finite numeric (Inf/-Inf) -> empty field
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
