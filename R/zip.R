# Deterministic STORED (uncompressed) zip writer, hand-rolled on writeBin.
# Rationale: system `zip` binaries and the zip package embed local mtimes,
# permissions, and platform extra fields, which breaks the FR-BUNDLE-8
# "deterministically rebuildable transport artifact" AC. This writer emits
# byte-identical archives for identical inputs: entries in C-locale path
# order, method 0 (stored), a single fixed DOS timestamp (SOURCE_DATE_EPOCH
# when set), UTF-8 name flag, no extra fields, no directory entries.
# Reading remains utils::unzip(unzip = "internal") — stored entries are
# universally supported (a .docx packed this way opens in Word).

# Little-endian unsigned integer -> n raw bytes. Numeric (double) arithmetic
# on purpose: crc32/sizes/offsets can exceed .Machine$integer.max and
# strtoi()/bitwAnd() would overflow at 2^31.
zip_le_bytes <- function(x, n) {
  x <- as.numeric(x)
  out <- raw(n)
  for (i in seq_len(n)) {
    out[i] <- as.raw(x %% 256)
    x <- x %/% 256
  }
  out
}

zip_crc32 <- function(data) {
  hex <- digest::digest(data, algo = "crc32", serialize = FALSE)
  if (nchar(hex) < 8) hex <- paste0(strrep("0", 8 - nchar(hex)), hex)
  pairs <- substring(hex, c(1, 3, 5, 7), c(2, 4, 6, 8))
  sum(vapply(pairs, function(p) strtoi(p, 16L), numeric(1)) * 256^(3:0))
}

# One shared MS-DOS timestamp for every entry. DOS time cannot represent
# dates before 1980; clamp so a SOURCE_DATE_EPOCH of 0 stays representable.
zip_dos_datetime <- function(time = NULL) {
  if (is.null(time)) {
    sde <- Sys.getenv("SOURCE_DATE_EPOCH", unset = "")
    time <- if (nzchar(sde)) {
      as.POSIXct(as.numeric(sde), origin = "1970-01-01", tz = "UTC")
    } else {
      Sys.time()
    }
  }
  t <- as.POSIXlt(time, tz = "UTC")
  year <- t$year + 1900L
  if (year < 1980L) return(list(time = 0, date = 33))  # 1980-01-01 00:00:00
  list(
    time = t$hour * 2048 + t$min * 32 + (t$sec %/% 2),
    date = (year - 1980) * 512 + (t$mon + 1) * 32 + t$mday
  )
}

# Write `files` (relative paths under root_dir, `/` separators) into a
# stored zip at zip_path. Default file set: everything under root_dir,
# including dotfiles, in C-locale order.
zip_write <- function(zip_path, root_dir, files = NULL, time = NULL) {
  if (is.null(files)) {
    files <- list.files(root_dir, recursive = TRUE, all.files = TRUE,
                        no.. = TRUE)
  }
  files <- sort_c(gsub("\\", "/", files, fixed = TRUE))
  entries <- lapply(files, function(name) {
    src <- file.path(root_dir, name)
    if (!file.exists(src)) {
      avior_abort(paste0("zip: file not found: ", src))
    }
    readBin(src, "raw", file.size(src))
  })
  names(entries) <- files
  zip_write_entries(zip_path, entries, time = time)
}

# Low-level writer over in-memory entries (named list: entry name -> raw
# payload), written in the given order. zip_write() is the file-tree
# front end; tests use this directly to craft hostile archives.
zip_write_entries <- function(zip_path, entries, time = NULL) {
  files <- names(entries)
  dos <- zip_dos_datetime(time)

  locals <- vector("list", length(files))
  centrals <- vector("list", length(files))
  offset <- 0
  for (i in seq_along(files)) {
    name <- files[i]
    data <- entries[[i]]
    name_raw <- charToRaw(enc2utf8(name))
    crc <- zip_crc32(data)
    size <- length(data)
    fixed <- c(
      zip_le_bytes(20, 2),            # version needed
      zip_le_bytes(0x0800, 2),        # flags: UTF-8 names
      zip_le_bytes(0, 2),             # method: stored
      zip_le_bytes(dos$time, 2), zip_le_bytes(dos$date, 2),
      zip_le_bytes(crc, 4),
      zip_le_bytes(size, 4), zip_le_bytes(size, 4),
      zip_le_bytes(length(name_raw), 2),
      zip_le_bytes(0, 2)              # extra length
    )
    locals[[i]] <- c(zip_le_bytes(0x04034b50, 4), fixed, name_raw, data)
    centrals[[i]] <- c(
      zip_le_bytes(0x02014b50, 4),
      zip_le_bytes(20, 2),            # version made by
      fixed,
      zip_le_bytes(0, 2),             # comment length
      zip_le_bytes(0, 2),             # disk number
      zip_le_bytes(0, 2),             # internal attributes
      zip_le_bytes(0, 4),             # external attributes
      zip_le_bytes(offset, 4),
      name_raw
    )
    offset <- offset + length(locals[[i]])
  }

  central <- unlist(centrals)
  eocd <- c(
    zip_le_bytes(0x06054b50, 4),
    zip_le_bytes(0, 2), zip_le_bytes(0, 2),
    zip_le_bytes(length(files), 2), zip_le_bytes(length(files), 2),
    zip_le_bytes(length(central), 4),
    zip_le_bytes(offset, 4),
    zip_le_bytes(0, 2)
  )

  con <- file(zip_path, open = "wb")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  writeBin(c(unlist(locals), central, eocd), con)
  invisible(zip_path)
}
