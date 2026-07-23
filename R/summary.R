# The summary digest accumulates notable events (warnings, errors, and any step
# that ends badly) with a breadcrumb path, so logtree_summary() can report "what
# went wrong" at the end of a run without scrolling the whole timeline. It is
# fed by record_summary(), called at the top of emit() (R/appenders.R), and
# cleared by logtree_reset() -- it is a stateful accumulator, not a sink (sinks
# render every event and survive reset; this must clear on reset).

# Does `desc` sit at or below `anc` in the tree? True when the paths are equal
# or `anc` is a prefix of `desc`. Used to collapse an uncaught error's
# handler-leaf plus every ancestor close into a single entry at its deepest
# point (see record_summary()).
covers <- function(anc, desc) {
  length(desc) >= length(anc) && identical(desc[seq_along(anc)], anc)
}

# Called for every emitted event (top of emit()). Records the candidates:
#   * leaf   -- iff summary = TRUE, or (summary = NA and it is a warning/error).
#   * close  -- iff the step resolved to error/warning/interrupted AND no
#     already-buffered entry sits at or below its path (dedup: keeps one entry
#     per failure at its deepest point). Closes fire deepest-first, so the
#     deeper entry is always buffered before the shallower ancestor arrives.
record_summary <- function(event) {
  if (identical(event$kind, "leaf")) {
    sm <- event$summary
    keep <- isTRUE(sm) ||
      (is.na(sm) && event$status %in% c("warning", "error"))
    if (!keep) return(invisible(NULL))
    the$summary[[length(the$summary) + 1L]] <- list(
      kind = "leaf", status = event$status, msg = event$label,
      path = current_path(), elapsed = NA_real_
    )
    return(invisible(NULL))
  }
  if (event$kind %in% c("close", "group_close")) {
    st <- resolved_status(event$entry$status)
    if (!st %in% c("error", "warning", "interrupted")) return(invisible(NULL))
    this_path <- current_path()
    covered <- any(vapply(
      the$summary,
      function(e) covers(this_path, e$path),
      logical(1)
    ))
    if (covered) return(invisible(NULL))
    the$summary[[length(the$summary) + 1L]] <- list(
      kind = "step", status = st, msg = NULL,
      path = this_path, elapsed = event$entry$elapsed
    )
  }
  invisible(NULL)
}

#' Report a digest of notable events
#'
#' Prints a compact end-of-run digest of everything worth attention that
#' happened since the last [logtree_reset()]: every warning and error leaf line,
#' plus any step that closed with a `warning`, `error`, or `interrupted` status.
#' Each entry shows the status glyph, the breadcrumb path to where it happened,
#' and the message (for leaf lines) or an outcome word (for steps).
#'
#' Unlike scrolling the live tree, the digest surfaces breakage even when no
#' [with_logging()] handler was installed -- interrupted steps are picked up
#' from their close lines. Ordinary `info` / `success` lines are excluded unless
#' logged with `summary = TRUE`; a warning or error can be excluded with
#' `summary = FALSE`.
#'
#' @param filter Optional character vector of statuses to include, e.g.
#'   `"error"` or `c("warning", "interrupted")`. Only entries whose status
#'   matches are printed and returned; recognised statuses are `"error"`,
#'   `"warning"`, `"interrupted"`, and the pinned leaf statuses `"info"`,
#'   `"success"`, `"debug"`. `NULL` (the default) reports every entry.
#' @return The recorded entries, invisibly: a list of records, each a list with
#'   `kind`, `status`, `msg`, `path` (character vector), and `elapsed`.
#' @seealso [with_logging()], [logtree_reset()]
#' @export
#' @examples
#' logtree_reset()
#' f <- function() {
#'   log_step("Load data")
#'   log_warn("coerced 3 rows")
#' }
#' f()
#' logtree_summary()
logtree_summary <- function(filter = NULL) {
  entries <- the$summary
  if (!is.null(filter)) {
    keep <- vapply(entries, function(e) e$status %in% filter, logical(1))
    entries <- entries[keep]
  }
  if (length(entries) == 0L) {
    cat("Summary: nothing to report\n")
    return(invisible(entries))
  }
  statuses <- vapply(entries, function(e) e$status, character(1))
  n_error       <- sum(statuses == "error")
  n_warning     <- sum(statuses == "warning")
  n_interrupted <- sum(statuses == "interrupted")
  # Anything left is a pinned line (summary = TRUE on an info/success/debug),
  # counted together so the header total always matches the lines printed.
  n_pinned      <- length(entries) - n_error - n_warning - n_interrupted
  plural <- function(n, word) sprintf("%d %s%s", n, word, if (n == 1L) "" else "s")
  parts <- c(
    if (n_error       > 0L) plural(n_error, "error"),
    if (n_warning     > 0L) plural(n_warning, "warning"),
    if (n_interrupted > 0L) sprintf("%d interrupted", n_interrupted),
    if (n_pinned      > 0L) sprintf("%d pinned", n_pinned)
  )
  cat("Summary: ", paste(parts, collapse = ", "), "\n", sep = "")
  for (e in entries) {
    path   <- paste(e$path, collapse = " > ")
    detail <- if (identical(e$kind, "leaf")) {
      e$msg
    } else {
      switch(e$status,
        error       = "failed",
        warning     = "completed with warning",
        interrupted = "did not complete",
        e$status
      )
    }
    cat(theme_glyph(e$status), " ", path, "  ", detail, "\n", sep = "")
  }
  invisible(entries)
}
