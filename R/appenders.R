emit <- function(event) {
  for (sink in the$sinks) sink(event)
}

console_sink <- function(event) {
  line <- switch(event$kind,
    open        = format_open(event$entry),
    close       = format_close(event$entry),
    group       = format_group_header(event$entry),
    group_close = format_close(event$entry),
    leaf        = format_leaf(event$status, event$label, event$depth,
                              corner = isTRUE(event$terminal))
  )
  cat(line, "\n", sep = "")
}

file_text_sink <- function(path) {
  force(path)
  function(event) {
    # Always plain ASCII, no ANSI -- independent of the active console
    # theme (design doc section 6).
    line <- switch(event$kind,
      open        = format_open(event$entry, theme = glyphs_ascii, color = FALSE),
      close       = format_close(event$entry, theme = glyphs_ascii, color = FALSE),
      group       = format_group_header(event$entry, theme = glyphs_ascii, color = FALSE),
      group_close = format_close(event$entry, theme = glyphs_ascii, color = FALSE),
      leaf        = format_leaf(event$status, event$label, event$depth, theme = glyphs_ascii, color = FALSE, corner = isTRUE(event$terminal))
    )
    cat(line, "\n", file = path, append = TRUE, sep = "")
  }
}

esc_json_string <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  paste0("\"", x, "\"")
}

json_scalar <- function(x) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) return("null")
  if (is.numeric(x)) return(format(x, scientific = FALSE, trim = TRUE))
  esc_json_string(x)
}

# Hand-rolled scalar encoder for this one fixed, known event schema --
# avoids adding jsonlite to Imports for a shape this small (design doc
# section 6).
to_json_line <- function(event) {
  paste0(
    "{",
    "\"ts\":", json_scalar(event$ts), ",",
    "\"level\":", json_scalar(event$level), ",",
    "\"id\":", json_scalar(event$id), ",",
    "\"parent_id\":", json_scalar(event$parent_id), ",",
    "\"depth\":", json_scalar(event$depth), ",",
    "\"label\":", json_scalar(event$label), ",",
    "\"elapsed\":", json_scalar(event$elapsed), ",",
    "\"status\":", json_scalar(event$status),
    "}"
  )
}

file_json_sink <- function(path) {
  force(path)
  function(event) {
    is_leaf <- identical(event$kind, "leaf")
    id      <- if (is_leaf) event$id else event$entry$id
    parent  <- if (is_leaf) event$parent_id else event$entry$parent_id
    depth   <- if (is_leaf) event$depth else event$entry$depth
    label   <- if (is_leaf) {
      event$label
    } else if (event$kind %in% c("group", "group_close")) {
      event$entry$name
    } else {
      event$entry$label
    }
    status  <- if (is_leaf) {
      event$status
    } else if (identical(event$kind, "open")) {
      "step"
    } else if (identical(event$kind, "group")) {
      "group"
    } else {
      if (identical(event$entry$status, "running")) "success" else event$entry$status
    }
    elapsed <- if (event$kind %in% c("close", "group_close")) event$entry$elapsed else NA_real_

    line <- to_json_line(list(
      ts        = as.numeric(Sys.time()),
      level     = event$kind,
      id        = id,
      parent_id = parent,
      depth     = depth,
      label     = label,
      elapsed   = elapsed,
      status    = status
    ))
    cat(line, "\n", file = path, append = TRUE, sep = "")
  }
}

#' Add a file sink
#'
#' Registers an additional output destination. Every logged event fans out
#' to the console sink (always on) and every registered file sink, so
#' console, text-file, and NDJSON outputs can all run simultaneously
#' (design doc section 6).
#'
#' @param path File path to append rendered log lines to.
#' @param format `"text"` for a plain ASCII tree (no ANSI, independent of
#'   the active console theme) or `"json"` for one NDJSON object per event.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' logtree_sink_file(tempfile(), format = "text")
#' with_logging({
#'   log_step("Step one")
#' })
logtree_sink_file <- function(path, format = c("text", "json")) {
  format <- match.arg(format)
  sink_fn <- if (identical(format, "json")) file_json_sink(path) else file_text_sink(path)
  the$sinks[[length(the$sinks) + 1L]] <- sink_fn
  invisible(NULL)
}
