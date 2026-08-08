# Fan one event out to every registered sink, in registration order
# (R/sinks.R holds the registry itself).
#
# A sink that throws must not take the rest of the fanout down with it: the
# logger is a witness to what went wrong, not a new source of failures. So each
# call is wrapped, the offender is skipped, and a warning naming it is raised
# once -- the id is marked in `the$sink_failed` *before* the warning goes out,
# and the warning itself only after the loop. That ordering is what keeps this
# terminating under with_logging(warnings = TRUE), where the warning is routed
# back into a leaf and re-enters emit(): the second pass finds the sink already
# marked and stays quiet.
emit <- function(event) {
  record_summary(event)
  # Stamp the event once, here, rather than letting each sink call Sys.time()
  # for itself: two sinks recording the same event must agree about when it
  # happened, and a run replayed from a file must line up with one replayed
  # from memory.
  event$ts <- wall_clock()
  problems <- character(0)
  for (id in names(the$sinks)) {
    fn <- the$sinks[[id]]$fn
    tryCatch(fn(event), error = function(e) {
      if (!id %in% the$sink_failed) {
        the$sink_failed  <- c(the$sink_failed, id)
        problems[[id]]  <<- conditionMessage(e)
      }
    })
  }
  for (id in names(problems)) {
    warning(sprintf("logtree sink '%s' threw and was skipped: %s", id, problems[[id]]),
            call. = FALSE)
  }
  invisible(NULL)
}

console_sink <- function(event) {
  line <- switch(event$kind,
    open        = format_open(event$entry),
    close       = format_close(event$entry),
    group       = format_group_header(event$entry),
    group_close = format_close(event$entry),
    leaf        = format_leaf(event$status, event$label, event$depth,
                              corner = isTRUE(event$terminal),
                              trace = event$trace)
  )
  cat(line, "\n", sep = "")
}

# The theme a text sink renders through: always the ascii preset, but with the
# trace column resolved per-event rather than taken from the preset.
#
# The preset ships `show = FALSE` like every other, so without this a text sink
# would silently disagree with a console that has trace switched on. `trace =
# NULL` (the default) means "whatever the console is doing", read at render time
# so enabling trace mid-run reaches the file too; an explicit value pins the sink
# independently. The common case -- trace off -- returns the preset untouched
# rather than copying a 17-element list per event.
text_sink_theme <- function(trace) {
  show <- if (is.null(trace)) resolve_trace_show(the$theme) else trace
  if (isFALSE(show)) return(glyphs_ascii)
  theme <- glyphs_ascii
  theme$trace$show <- show
  theme
}

file_text_sink <- function(path, trace = NULL) {
  force(path)
  force(trace)
  function(event) {
    # Always plain ASCII, no ANSI -- independent of the active console
    # theme (design doc section 6).
    theme <- text_sink_theme(trace)
    line <- switch(event$kind,
      open        = format_open(event$entry, theme = theme, color = FALSE),
      close       = format_close(event$entry, theme = theme, color = FALSE),
      group       = format_group_header(event$entry, theme = theme, color = FALSE),
      group_close = format_close(event$entry, theme = theme, color = FALSE),
      leaf        = format_leaf(event$status, event$label, event$depth, theme = theme, color = FALSE, corner = isTRUE(event$terminal), trace = event$trace)
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

# --- The structured event record --------------------------------------------
#
# Every non-rendering sink wants the same flattened view of an event, and the
# two that exist -- the NDJSON file sink and the memory sink (R/sinks.R) -- must
# not drift apart: a run replayed from a log file and the same run inspected in
# memory should say the same things. So the flattening lives here, once, and the
# schema is declared once in record_proto().
#
# The awkwardness it absorbs is that a leaf carries its fields directly while
# every other kind carries them on `entry`, and that a group has a `name` where
# a step has a `label`.

# One zero-length vector per column, in column order: the record's schema, and
# the prototype the memory sink's data.frame is built from.
record_proto <- function() {
  list(
    ts        = as.POSIXct(numeric(0), tz = "", origin = "1970-01-01"),
    level     = character(0),
    id        = integer(0),
    parent_id = integer(0),
    depth     = integer(0),
    label     = character(0),
    elapsed   = numeric(0),
    status    = character(0),
    fn        = character(0),
    file      = character(0),
    line      = integer(0)
  )
}

event_record <- function(event) {
  is_leaf <- identical(event$kind, "leaf")
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
  # A leaf carries its trace on the event; a step carries it on the entry,
  # captured when the step opened. Groups have none (see format_group_header).
  trace <- if (is_leaf) event$trace else event$entry$trace

  list(
    ts        = event$ts,
    level     = event$kind,
    id        = if (is_leaf) event$id else event$entry$id,
    parent_id = if (is_leaf) event$parent_id else event$entry$parent_id,
    depth     = if (is_leaf) event$depth else event$entry$depth,
    label     = label,
    elapsed   = if (event$kind %in% c("close", "group_close")) event$entry$elapsed else NA_real_,
    status    = status,
    fn        = trace$fn,
    file      = trace$file,
    line      = trace$line
  )
}

# Hand-rolled scalar encoder for this one fixed, known event schema --
# avoids adding jsonlite to Imports for a shape this small (design doc
# section 6).
#
# The `fn` / `file` / `line` trio is the call site. Unlike the console column it
# is not gated by the theme's `trace$show`: a structured log wants every field it
# can get, and json_scalar() already renders an absent one as null. They are
# still only *captured* when the slot is on, so with trace off they are null
# throughout -- consistent, and it costs a reader nothing.
to_json_line <- function(record) {
  paste0(
    "{",
    "\"ts\":", json_scalar(as.numeric(record$ts)), ",",
    "\"level\":", json_scalar(record$level), ",",
    "\"id\":", json_scalar(record$id), ",",
    "\"parent_id\":", json_scalar(record$parent_id), ",",
    "\"depth\":", json_scalar(record$depth), ",",
    "\"label\":", json_scalar(record$label), ",",
    "\"elapsed\":", json_scalar(record$elapsed), ",",
    "\"status\":", json_scalar(record$status), ",",
    "\"fn\":", json_scalar(record$fn), ",",
    "\"file\":", json_scalar(record$file), ",",
    "\"line\":", json_scalar(record$line),
    "}"
  )
}

file_json_sink <- function(path) {
  force(path)
  function(event) {
    cat(to_json_line(event_record(event)), "\n",
        file = path, append = TRUE, sep = "")
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
#' @param trace Whether this sink prints the call-site column (see the `trace`
#'   slot in [logtree_theme()]). `NULL` (the default) follows the active console
#'   theme, read afresh for each event, so switching trace on reaches the file
#'   too; `FALSE`, `TRUE` or `"problems"` pins this sink independently of the
#'   console. Text sinks only: a `"json"` sink always carries the `fn`, `file`
#'   and `line` fields, `null` when there is no call site to report.
#' @return The sink's id, invisibly -- pass it to [logtree_sink_remove()] to
#'   stop writing to this file.
#' @seealso [logtree_sink()] for a sink of your own, [logtree_sinks()] and
#'   [logtree_sink_remove()] for the registry.
#' @export
#' @examples
#' logtree_reset()
#' logtree_sink_file(tempfile(), format = "text")
#' with_logging({
#'   log_step("Step one")
#' })
#'
#' # A file that records call sites even with the console column off.
#' logtree_sink_file(tempfile(), format = "text", trace = TRUE)
logtree_sink_file <- function(path, format = c("text", "json"), trace = NULL) {
  format <- match.arg(format)
  sink_fn <- if (identical(format, "json")) {
    file_json_sink(path)
  } else {
    file_text_sink(path, trace = trace)
  }
  # A sink asking for trace in its own right has to switch *capture* on, or it
  # would render a column that was never populated. See trace_enabled().
  invisible(register_sink(
    sink_fn,
    trace = !is.null(trace) && !isFALSE(trace)
  ))
}
