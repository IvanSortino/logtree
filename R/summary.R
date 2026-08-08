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
      path = current_path(), elapsed = NA_real_, trace = event$trace
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
      path = this_path, elapsed = event$entry$elapsed,
      trace = event$entry$trace
    )
  }
  invisible(NULL)
}

# --- Divider ---------------------------------------------------------------
# The digest is printed straight after the last log line, which makes it read
# as one more branch of the tree. A blank gap plus a cli rule sets it apart as
# its own block. The defaults live in the active theme's `summary` slot
# (gap / rule / line), read through theme_field() (R/theme.R), so appearance is
# customised in one place -- logtree_theme() -- and logtree_summary()'s own
# `gap` / `rule` arguments are per-call overrides of it.

resolve_gap <- function(gap, theme = the$theme) {
  if (is.null(gap)) gap <- theme_field("summary", "gap", 1L, theme)
  if (!is.numeric(gap) || length(gap) != 1L || is.na(gap) ||
      gap < 0 || gap != as.integer(gap)) {
    stop("`gap` must be a non-negative whole number.", call. = FALSE)
  }
  as.integer(gap)
}

resolve_rule <- function(rule, theme = the$theme) {
  if (is.null(rule)) rule <- theme_field("summary", "rule", TRUE, theme)
  ok <- (is.logical(rule) && length(rule) == 1L && !is.na(rule)) ||
    (is.character(rule) && length(rule) == 1L && !is.na(rule))
  if (!ok) {
    stop("`rule` must be TRUE, FALSE, or a single title string.", call. = FALSE)
  }
  rule
}

# Join breadcrumb nodes with the theme's separator. The path nodes carry the
# `crumb$path_color` emphasis and the separators their own (dimmer) style, so
# the trail reads as context; `plain_last` leaves a leaf's message -- the
# terminal node -- unstyled, since that is content, not path.
format_crumb <- function(nodes, plain_last = FALSE, theme = the$theme,
                         color = TRUE) {
  n <- length(nodes)
  if (n == 0L) return("")
  path_color <- theme[["crumb"]][["path_color"]]
  styled <- vapply(seq_len(n), function(i) {
    if (plain_last && i == n) nodes[[i]] else colorize(nodes[[i]], path_color, color)
  }, character(1))
  sep <- colorize(
    theme_field("crumb", "glyph", " > ", theme),
    theme[["crumb"]][["color"]], color
  )
  paste(styled, collapse = sep)
}

# Prints the gap, then the rule and/or the plain header line:
#   rule = TRUE    -- header becomes the rule's label (no separate line)
#   rule = FALSE   -- plain header line, no rule
#   rule = "title" -- rule labelled "title", header line below it
print_summary_header <- function(header, gap, rule) {
  if (gap > 0L) cat(strrep("\n", gap))
  if (isFALSE(rule)) {
    cat(header, "\n", sep = "")
    return(invisible(NULL))
  }
  label <- if (isTRUE(rule)) header else rule
  line <- theme_field("summary", "line", 1L)
  cat(cli::rule(left = label, line = line), "\n", sep = "")
  if (!isTRUE(rule)) cat(header, "\n", sep = "")
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
#' The digest's appearance comes from the active theme, so it is customised
#' through [logtree_theme()] like everything else: the `crumb` slot sets the
#' breadcrumb separator and the emphasis on the path nodes, the `summary` slot
#' the divider (`gap`, `rule`, `line`). `gap` and `rule` below override the
#' theme for a single call.
#'
#' @param filter Optional character vector of statuses to include, e.g.
#'   `"error"` or `c("warning", "interrupted")`. Only entries whose status
#'   matches are printed and returned; recognised statuses are `"error"`,
#'   `"warning"`, `"interrupted"`, and the pinned leaf statuses `"info"`,
#'   `"success"`, `"debug"`. `NULL` (the default) reports every entry.
#' @param depth Optional positive integer limiting how many trailing (deepest)
#'   breadcrumb nodes are printed. The message counts as the terminal node, so
#'   `depth = 1` prints just the message (or, for a step entry, its innermost
#'   step), `depth = 2` the message plus its immediate parent, and so on.
#'   `NULL` (the default) prints the full breadcrumb. Affects printing only; the
#'   returned entries always carry the full `path`.
#' @param gap Number of blank lines printed between the last log line and the
#'   digest; `0` prints the digest flush against the tree. `NULL` (the default)
#'   takes the active theme's `summary$gap` (`1` in every built-in preset).
#' @param rule Divider drawn above the digest. `TRUE` draws a [cli::rule()]
#'   labelled with the digest header, so the counts become the rule's title
#'   instead of a separate line; `FALSE` draws no rule and keeps the plain
#'   header line; a character string draws the rule with that title and prints
#'   the header line below it. `NULL` (the default) takes the active theme's
#'   `summary$rule` (`TRUE` in every built-in preset).
#' @return The recorded entries, invisibly: a list of records, each a list with
#'   `kind`, `status`, `msg`, `path` (character vector), `elapsed`, and `trace`
#'   (the call site: a list of `fn`, `file` and `line`, or `NULL` when the
#'   `trace` theme slot was off and nothing was captured).
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
#'
#' # Flush against the tree, with a titled divider.
#' logtree_summary(gap = 0, rule = "Run report")
#'
#' # Set the layout and the breadcrumb symbol once, on the theme.
#' logtree_theme(list(
#'   summary = list(gap = 2, rule = FALSE),
#'   crumb   = list(glyph = " / ")
#' ))
#' logtree_summary()
#' logtree_theme("unicode")
logtree_summary <- function(filter = NULL, depth = NULL,
                            gap = NULL, rule = NULL) {
  gap  <- resolve_gap(gap)
  rule <- resolve_rule(rule)
  if (!is.null(depth)) {
    if (!is.numeric(depth) || length(depth) != 1L || is.na(depth) ||
        depth < 1 || depth != as.integer(depth)) {
      stop("`depth` must be NULL or a positive whole number.", call. = FALSE)
    }
    depth <- as.integer(depth)
  }
  entries <- the$summary
  if (!is.null(filter)) {
    keep <- vapply(entries, function(e) e$status %in% filter, logical(1))
    entries <- entries[keep]
  }
  if (length(entries) == 0L) {
    print_summary_header("Summary: nothing to report", gap, rule)
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
  print_summary_header(
    paste0("Summary: ", paste(parts, collapse = ", ")), gap, rule
  )
  # depth (when set) keeps only the trailing `depth` breadcrumb nodes.
  clip <- function(nodes) if (is.null(depth)) nodes else utils::tail(nodes, depth)
  for (e in entries) {
    if (identical(e$kind, "leaf")) {
      # The leaf's message is the terminal node of its breadcrumb, so join it to
      # the ancestor path with the same separator -- but unstyled, so the
      # emphasised path reads as the trail leading to it.
      crumb <- with_trace(
        format_crumb(clip(c(e$path, e$msg)), plain_last = TRUE),
        format_trace_digest(e$trace, e$status)
      )
      cat(compose_flat_line(theme_glyph(e$status), crumb), "\n", sep = "")
    } else {
      # Step entries carry no message; render the switch()-mapped outcome word
      # after the path, set off by two spaces (a description, not a path node).
      path   <- format_crumb(clip(e$path))
      detail <- switch(e$status,
        error       = "failed",
        warning     = "completed with warning",
        interrupted = "did not complete",
        e$status
      )
      cat(compose_flat_line(
            theme_glyph(e$status),
            with_trace(paste0(path, "  ", detail),
                       format_trace_digest(e$trace, e$status))
          ), "\n", sep = "")
    }
  }
  invisible(entries)
}
