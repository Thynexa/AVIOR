# DOCX serialization of the report block tree (issue #33). Hand-rolled
# minimal OOXML — headings, paragraphs, tables, page breaks — packed with
# the deterministic stored-zip writer, so report.docx is byte-identical
# under SOURCE_DATE_EPOCH and needs no pandoc/Quarto system dependency.

xml_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("'", "&apos;", x, fixed = TRUE)
}

docx_run <- function(text, bold = FALSE) {
  paste0("<w:r>",
         if (bold) "<w:rPr><w:b/></w:rPr>" else "",
         "<w:t xml:space=\"preserve\">", xml_escape(text), "</w:t></w:r>")
}

docx_para <- function(text, style = NULL, bold = FALSE, border = FALSE) {
  ppr <- ""
  if (!is.null(style) || border) {
    ppr <- paste0(
      "<w:pPr>",
      if (!is.null(style)) paste0("<w:pStyle w:val=\"", style, "\"/>") else "",
      if (border) paste0(
        "<w:pBdr>",
        paste0("<w:", c("top", "left", "bottom", "right"),
               " w:val=\"single\" w:sz=\"12\" w:space=\"4\" w:color=\"B42318\"/>",
               collapse = ""),
        "</w:pBdr>") else "",
      "</w:pPr>")
  }
  paste0("<w:p>", ppr, docx_run(text, bold = bold), "</w:p>")
}

docx_page_break <- function() {
  "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
}

docx_cell <- function(text, bold = FALSE) {
  paste0("<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr>",
         "<w:p>", docx_run(text, bold = bold), "</w:p></w:tc>")
}

docx_table <- function(header, rows, first_col_bold = FALSE) {
  ncols <- if (!is.null(header)) length(header) else length(rows[[1]])
  borders <- paste0(
    "<w:tblBorders>",
    paste0("<w:", c("top", "left", "bottom", "right", "insideH", "insideV"),
           " w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"CBD5E0\"/>",
           collapse = ""),
    "</w:tblBorders>")
  grid <- paste0("<w:tblGrid>",
                 paste(rep("<w:gridCol w:w=\"2000\"/>", ncols), collapse = ""),
                 "</w:tblGrid>")
  head_xml <- if (!is.null(header)) {
    paste0("<w:tr>", paste(vapply(header, function(h) docx_cell(h, bold = TRUE),
                                  character(1)), collapse = ""), "</w:tr>")
  } else {
    ""
  }
  body_xml <- paste(vapply(rows, function(r) {
    cells <- vapply(seq_along(r), function(j) {
      docx_cell(r[j], bold = first_col_bold && j == 1L)
    }, character(1))
    paste0("<w:tr>", paste(cells, collapse = ""), "</w:tr>")
  }, character(1)), collapse = "")
  paste0("<w:tbl><w:tblPr>",
         "<w:tblW w:w=\"0\" w:type=\"auto\"/>", borders,
         "</w:tblPr>", grid, head_xml, body_xml, "</w:tbl>",
         # Word requires a paragraph between/after tables
         "<w:p/>")
}

docx_document_xml <- function(blocks) {
  n <- length(blocks)
  body <- vapply(seq_len(n), function(i) {
    b <- blocks[[i]]
    switch(
      b$type,
      heading = docx_para(b$text, style = paste0("Heading", b$level)),
      para = docx_para(b$text),
      banner = docx_para(b$text, bold = TRUE, border = TRUE),
      bullets = paste(vapply(b$items, function(it) {
        docx_para(paste0("- ", it))
      }, character(1)), collapse = ""),
      kv_table = docx_table(NULL, b$rows, first_col_bold = TRUE),
      table = docx_table(b$header, b$rows),
      page_break = docx_page_break()
    )
  }, character(1))
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">",
    "<w:body>", paste(body, collapse = ""),
    "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>",
    "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/>",
    "</w:sectPr></w:body></w:document>")
}

docx_styles_xml <- function() {
  heading <- function(id, size, before) {
    paste0(
      "<w:style w:type=\"paragraph\" w:styleId=\"Heading", id, "\">",
      "<w:name w:val=\"heading ", id, "\"/><w:basedOn w:val=\"Normal\"/>",
      "<w:pPr><w:spacing w:before=\"", before, "\" w:after=\"120\"/>",
      "<w:outlineLvl w:val=\"", id - 1L, "\"/></w:pPr>",
      "<w:rPr><w:b/><w:sz w:val=\"", size, "\"/>",
      "<w:color w:val=\"2B5C8A\"/></w:rPr></w:style>")
  }
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">",
    "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">",
    "<w:name w:val=\"Normal\"/>",
    "<w:pPr><w:spacing w:after=\"120\"/></w:pPr>",
    "<w:rPr><w:sz w:val=\"22\"/></w:rPr></w:style>",
    heading(1L, 36, 240), heading(2L, 28, 360),
    "</w:styles>")
}

docx_content_types <- function() {
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">",
    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
    "<Default Extension=\"xml\" ContentType=\"application/xml\"/>",
    "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>",
    "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>",
    "</Types>")
}

docx_rels_root <- function() {
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/>",
    "</Relationships>")
}

docx_rels_document <- function() {
  paste0(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>",
    "</Relationships>")
}

render_report_docx <- function(blocks, title, path) {
  parts <- list(
    "[Content_Types].xml" = charToRaw(enc2utf8(docx_content_types())),
    "_rels/.rels" = charToRaw(enc2utf8(docx_rels_root())),
    "word/_rels/document.xml.rels" = charToRaw(enc2utf8(docx_rels_document())),
    "word/document.xml" = charToRaw(enc2utf8(docx_document_xml(blocks))),
    "word/styles.xml" = charToRaw(enc2utf8(docx_styles_xml()))
  )
  zip_write_entries(path, parts)
  invisible(path)
}
