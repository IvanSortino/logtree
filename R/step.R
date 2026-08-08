current_parent_id <- function() {
  n <- length(the$stack)
  if (n == 0L) return(0L)
  the$stack[[n]]$id
}

# Visual depth of the innermost open node. In the pure auto model this equals
# length(the$stack), but explicit parent-linking (log_open(parent=)) can place
# a node at a shallower depth than its stack position, so depth must be read
# from the entry itself, never inferred from stack length.
current_depth <- function() {
  n <- length(the$stack)
  if (n == 0L) return(0L)
  the$stack[[n]]$depth
}

# Breadcrumb of the currently-open ancestor chain, outermost-first: step labels
# and group names in stack order. Used by the summary digest to record where a
# notable event happened. At emit() time a closing entry is still on the stack
# (removal happens after the emit returns), so it appears as the last element.
current_path <- function() {
  out <- character(0)
  for (e in the$stack) {
    if (identical(e$kind, "step")) {
      out <- c(out, e$label)
    } else if (identical(e$kind, "group")) {
      out <- c(out, e$name)
    }
  }
  out
}

parse_group <- function(group) {
  if (length(group) != 1L) {
    stop("`group` must be a length-1 named vector, e.g. c(name = value).", call. = FALSE)
  }
  nm    <- names(group)
  value <- unname(group)
  name  <- if (is.null(nm) || is.na(nm) || !nzchar(nm)) as.character(value) else nm
  list(name = name, value = value)
}

# Close any lingering (member-less) group at the top of the stack that the
# incoming event does not belong to. A group is only ever exposed at the top
# once its member step has closed, so popping it here is always safe. A grouped
# step matching the top group (same name + value) is kept so it can be reused.
settle_groups <- function(name = NULL, value = NULL) {
  repeat {
    n <- length(the$stack)
    if (n == 0L) break
    top <- the$stack[[n]]
    if (!identical(top$kind, "group")) break
    if (!is.null(name) && identical(top$name, name) && identical(top$value, value)) break
    top$elapsed <- now() - top$start
    emit(list(kind = "group_close", entry = top))
    the$stack[[n]] <- NULL
  }
  invisible(NULL)
}

open_or_reuse_group <- function(name, value) {
  settle_groups(name, value)
  n   <- length(the$stack)
  top <- if (n > 0L) the$stack[[n]] else NULL
  if (!is.null(top) && identical(top$kind, "group") &&
      identical(top$name, name) && identical(top$value, value)) {
    return(top$id)
  }
  id <- the$next_id
  the$next_id <- id + 1L
  entry <- list(
    id        = id,
    parent_id = current_parent_id(),
    kind      = "group",
    name      = name,
    value     = value,
    depth     = current_depth() + 1L,
    start     = now(),
    status    = "running"
  )
  the$stack[[length(the$stack) + 1L]] <- entry
  emit(list(kind = "group", entry = entry))
  id
}

# A group aggregates the status of its member steps: each member's resolved
# status folds up into the group as it closes, so the group's own close line
# reflects the worst thing that happened underneath it (running < success <
# warning < error). Non-group / non-matching parents are ignored.
elevate_group_status <- function(id, status) {
  idx <- Find(function(i) the$stack[[i]]$id == id, seq_along(the$stack))
  if (is.null(idx)) return(invisible(NULL))
  if (!identical(the$stack[[idx]]$kind, "group")) return(invisible(NULL))
  if (status_severity(status) > status_severity(the$stack[[idx]]$status)) {
    the$stack[[idx]]$status <- status
  }
  invisible(NULL)
}

# Content-key reconcile (top-level line-by-line / re-run support).
#
# At top level the caller frame is globalenv(), which never exits mid-session,
# so a step's deferred close never fires and re-running a block would nest the
# new run *under* the previous run's still-open steps. To keep depth stable,
# top-level log_step()/log_open() carry a content `key` (the label) plus the
# call-site `srcref`. Before pushing, if that key matches a still-open step we
# re-anchor to it instead of descending. Colliding labels are disambiguated by
# srcref when available (same call site -> reuse; different -> a genuinely
# distinct step -> nest); with no srcref we reuse the outermost label match.
# Returns the stack index to reuse, or NULL to push a fresh step.
reconcile_open_step <- function(key, srcref) {
  if (is.null(key)) return(NULL)
  idxs <- Filter(function(i) {
    e <- the$stack[[i]]
    identical(e$kind, "step") && identical(e$key, key)
  }, seq_along(the$stack))
  if (length(idxs) == 0L) return(NULL)
  if (!is.null(srcref) && !is.na(srcref)) {
    exact <- Find(function(i) identical(the$stack[[i]]$srcref, srcref), idxs)
    if (!is.null(exact)) return(exact)
    # Same label but a different call site is open: nest a new step instead.
    return(NULL)
  }
  idxs[[1L]]
}

# "file:line" of a call site, or NA when source references are unavailable
# (e.g. keep.source = FALSE under non-interactive Rscript). NA disables srcref
# disambiguation, leaving the portable label-only reconcile in force.
src_location <- function(call) {
  line <- utils::getSrcLocation(call, "line")
  if (is.null(line) || is.na(line)) return(NA_character_)
  file <- utils::getSrcFilename(call)
  if (is.null(file) || !nzchar(file)) file <- "<text>"
  paste0(basename(file), ":", line)
}

push_step <- function(label, glyph = NULL, group = NULL, parent = NULL,
                      key = NULL, srcref = NULL) {
  if (!is.null(parent)) {
    p <- find_stack_entry(parent)
    if (is.null(p)) {
      stop(sprintf("parent step %s is not open.", parent), call. = FALSE)
    }
    parent_id <- parent
    depth     <- p$depth + 1L
  } else if (is.null(group)) {
    idx <- reconcile_open_step(key, srcref)
    if (!is.null(idx)) {
      # Re-anchor to the matched open step: close everything deeper, then
      # re-emit its open line so the re-run re-renders at the same depth.
      if (length(the$stack) > idx) {
        close_step(the$stack[[idx + 1L]]$id)
      }
      entry <- the$stack[[idx]]
      entry$start  <- now()
      entry$status <- "running"
      the$stack[[idx]] <- entry
      emit(list(kind = "open", entry = entry))
      return(entry)
    }
    settle_groups()
    parent_id <- current_parent_id()
    depth     <- current_depth() + 1L
  } else {
    g <- parse_group(group)
    parent_id <- open_or_reuse_group(g$name, g$value)
    depth     <- current_depth() + 1L
  }
  # Opening a step at `depth` retires any still-open node at the same or
  # greater depth: those are finished sibling/cousin subtrees, not ancestors
  # of the new node. In the default path `depth` is always innermost + 1, so
  # nothing qualifies and nesting is unchanged; this only unwinds when an
  # explicit `parent` places the new step beside an already-open sibling.
  while (length(the$stack) > 0L &&
         the$stack[[length(the$stack)]]$depth >= depth) {
    close_step(the$stack[[length(the$stack)]]$id)
  }
  id <- the$next_id
  the$next_id <- id + 1L
  entry <- list(
    id        = id,
    parent_id = parent_id,
    kind      = "step",
    label     = label,
    start     = now(),
    depth     = depth,
    status    = "running",
    glyph     = glyph,
    key       = key,
    srcref    = srcref
  )
  the$stack[[length(the$stack) + 1L]] <- entry
  emit(list(kind = "open", entry = entry))
  entry
}

find_stack_entry <- function(id) {
  idx <- Find(function(i) the$stack[[i]]$id == id, seq_along(the$stack))
  if (is.null(idx)) return(NULL)
  the$stack[[idx]]
}

set_stack_entry_status <- function(id, status) {
  idx <- Find(function(i) the$stack[[i]]$id == id, seq_along(the$stack))
  if (is.null(idx)) return(invisible(NULL))
  the$stack[[idx]]$status <- status
  invisible(NULL)
}

resolved_status <- function(status) {
  if (identical(status, "running")) "success" else status
}

close_step <- function(id, silent = FALSE) {
  idx <- Find(function(i) the$stack[[i]]$id == id, seq_along(the$stack))
  if (is.null(idx)) return(invisible(NULL))
  # Cascade-close deepest-first down to (and including) idx. This keeps the
  # stack correct even if closing arrives out of the expected order (e.g. the
  # same-frame-sibling pattern in log_step("A"); log_step("B")).
  #
  # `silent = TRUE` pops the same entries but emits no close/group_close event,
  # so no "Done" line is printed (used by the `close =` force-close: the log
  # line itself already served as the section's terminal). Status is still
  # folded up into any parent group, so a silently-closed member still colours
  # the group's eventual close line.
  result <- NULL
  for (i in rev(seq(idx, length(the$stack)))) {
    entry <- the$stack[[i]]
    entry$elapsed <- now() - entry$start
    if (identical(entry$kind, "group")) {
      # A group closes with its own corner line, statused from its members.
      if (!silent) emit(list(kind = "group_close", entry = entry))
    } else {
      if (!silent) emit(list(kind = "close", entry = entry))
      # Fold this step's outcome up into its parent group (if any). The
      # parent sits at a lower index and is still on the stack here, so it
      # picks up the elevation before its own close line is emitted.
      elevate_group_status(entry$parent_id, resolved_status(entry$status))
      if (i == idx) {
        result <- list(status = resolved_status(entry$status), elapsed = entry$elapsed)
      }
    }
    the$stack[[i]] <- NULL
  }
  invisible(result)
}

# Force-close the innermost open section (step or group) without emitting a
# close line. Used by the leaf `close = TRUE` path, where the leaf just emitted
# is the section's visible terminal line.
close_current_section_silent <- function() {
  id <- current_parent_id()
  if (id == 0L) return(invisible(NULL))
  close_step(id, silent = TRUE)
}

finalize_step <- function(id, sentinel) {
  rv    <- returnValue(sentinel)
  entry <- find_stack_entry(id)
  if (!is.null(entry) && identical(rv, sentinel) && identical(entry$status, "running")) {
    # Abnormal (error-driven) exit with no with_logging() Tier-2 handler
    # having already elevated this step's status to "error" -- render as
    # interrupted/dimmed rather than a false success glyph.
    set_stack_entry_status(id, "interrupted")
  }
  close_step(id)
}

#' Open a logged step
#'
#' `log_step()` is intended to be called from *inside a function*: it prints an
#' opening line for `msg` and registers an automatic close that fires when the
#' *calling* function's frame exits -- whether by normal return, early
#' `return()`, or an uncaught error propagating through it. Because the close is
#' registered in the caller's frame rather than inside `log_step()` itself,
#' nesting depth always stays in sync, even across errors. At top level, where
#' there is no enclosing function frame to close on, use [log_open()] /
#' [log_close()] instead.
#'
#' Opening a step at the same depth as an already-open step retires that earlier
#' sibling automatically -- its close line is printed with no explicit
#' [log_close()] call. In the default nested pattern each `log_step()` descends
#' one level deeper, so this same-level retirement applies when you place steps
#' side by side via an explicit `parent`.
#'
#' @param msg Character scalar. The step's label.
#' @param glyph Optional character scalar overriding this step's glyph.
#' @param parent Optional step handle (an id returned by [log_open()]/
#'   `log_step()`) of a currently-open step to nest this one under. Defaults to
#'   the innermost open step. The target must still be open, else an error.
#' @param group Optional named length-1 vector `c(name = value)`. Adjacent
#'   `log_step()` calls sharing the same `value` are grouped under a single
#'   `< name >` header line. The value is the match key; the name is displayed.
#' @param close Logical. When `TRUE`, the step is force-closed silently as soon
#'   as its opening line is printed: a header-only marker with no children and
#'   no `Done` line (and no automatic close is registered). Defaults to `FALSE`.
#' @param key Optional character scalar giving this step a stable identity for
#'   re-run reconciliation. At top level (the global env) the label is used
#'   automatically, so re-running the same line re-anchors to that node instead
#'   of nesting under the previous run's leftovers. Pass `key` to override the
#'   automatic label key, or to keep two same-label steps that are open at once
#'   distinct. Ignored when `parent` is supplied.
#' @return The step's internal id, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' f <- function() {
#'   log_step("Doing work")
#' }
#' f()
log_step <- function(msg, glyph = NULL, parent = NULL, group = NULL,
                     close = FALSE, key = NULL) {
  caller <- rlang::caller_env()
  srcref <- NULL
  if (is.null(key) && is.null(parent) && identical(caller, globalenv())) {
    # Top-level call: key on the label so re-running this line re-anchors to
    # the same node instead of nesting; srcref disambiguates same-label steps.
    key    <- msg
    srcref <- src_location(sys.call())
  }
  entry <- push_step(msg, glyph, group = group, parent = parent,
                     key = key, srcref = srcref)
  if (isTRUE(close)) {
    close_step(entry$id, silent = TRUE)
    return(invisible(entry$id))
  }
  if (identical(caller, globalenv())) {
    # No enclosing function frame: the caller's frame is the global env, which
    # only "exits" at session end, so the deferred close below never fires in
    # practice and the step lingers. Re-running the same top-level line now
    # re-anchors instead of nesting, but the step still won't auto-close --
    # nudge (once) toward the manual API.
    rlang::inform(
      c(
        "!" = "log_step() at top level won't auto-close: there is no function frame to close on.",
        "i" = "Use log_open() + log_close(), or wrap the call in a function."
      ),
      .frequency = "once",
      .frequency_id = "logtree_log_step_toplevel"
    )
  }
  sentinel <- new.env(parent = emptyenv())
  # At top level withr::defer() also emits its own "Setting global deferred
  # event(s)" message the first time -- redundant with the nudge above, so
  # silence it here rather than let both fire.
  suppressMessages(
    withr::defer(finalize_step(entry$id, sentinel), envir = caller, priority = "first")
  )
  invisible(entry$id)
}

#' Open a step under manual lifetime control
#'
#' Like [log_step()] but with no automatic close: the step stays open until
#' you close it yourself with [log_close()]. This is what you want at top
#' level (a script or the REPL), where there is no enclosing function frame
#' for `log_step()` to hang its close on. You may also attach the step to a
#' chosen open `parent` rather than the innermost open step, letting you build
#' the tree by hand.
#'
#' Opening a step at the same depth as an already-open step -- for example by
#' linking to a shared `parent` -- first closes that sibling and its
#' descendants, since a new sibling means the previous subtree is done.
#'
#' @param msg Character scalar. The step's label.
#' @param glyph Optional character scalar overriding this step's glyph.
#' @param parent Optional step handle (an id returned by `log_open()`/
#'   [log_step()]) of a currently-open step to nest this one under. Defaults to
#'   the innermost open step. The target must still be open, else an error.
#' @param group Optional named length-1 vector `c(name = value)`, as in
#'   [log_step()].
#' @param close Logical. When `TRUE`, the step is force-closed silently as soon
#'   as its opening line is printed: a header-only marker with no children and
#'   no `Done` line. Defaults to `FALSE`.
#' @param key Optional character scalar giving this step a stable identity for
#'   re-run reconciliation, as in [log_step()]. At top level the label is used
#'   automatically, so re-running the same `log_open()` line re-anchors to that
#'   node instead of nesting under the previous run's leftovers. Ignored when
#'   `parent` is supplied.
#' @return The step's id, invisibly. Capture it to pass to [log_close()] or as
#'   another step's `parent`.
#' @seealso [log_close()], [log_step()]
#' @export
#' @examples
#' logtree_reset()
#' s1 <- log_open("Step 1")
#' log_info("a child line")
#' log_close(s1)
log_open <- function(msg, glyph = NULL, parent = NULL, group = NULL,
                     close = FALSE, key = NULL) {
  caller <- rlang::caller_env()
  srcref <- NULL
  if (is.null(key) && is.null(parent) && identical(caller, globalenv())) {
    # Top-level call: key on the label so re-running this line re-anchors to
    # the same node instead of nesting; srcref disambiguates same-label steps.
    key    <- msg
    srcref <- src_location(sys.call())
  }
  entry <- push_step(msg, glyph, group = group, parent = parent,
                     key = key, srcref = srcref)
  if (isTRUE(close)) close_step(entry$id, silent = TRUE)
  invisible(entry$id)
}

#' Close a manually-opened step
#'
#' Closes the step opened by [log_open()] with the given `id`, cascading to
#' any of its still-open descendants (deepest-first). With no `id`, closes the
#' nearest open step, so simple last-in-first-out use needs no handle at all.
#'
#' A step's status only ever escalates via [log_warn()]/[log_error()] (see
#' status elevation); it never comes back down on its own, so a step that
#' logged an error and then recovered still closes with the error glyph. Pass
#' `status` to override that explicitly -- this force-assigns the step's
#' final status regardless of what it escalated to. Because `id = NULL`
#' resolves to the nearest open step for both [log_open()]-managed and
#' [log_step()]-managed steps alike, this also lets you close (and override)
#' a `log_step()` step early, before its automatic close-on-frame-exit fires.
#'
#' @param id Step handle from [log_open()]. If omitted, the nearest open step
#'   is closed.
#' @param status Optional character scalar overriding the step's final
#'   status: one of `"success"`, `"warning"`, or `"error"`. Bypasses the
#'   usual elevation rule instead of comparing against it.
#' @return A list with `status` and `elapsed` (seconds) for the step just
#'   closed, invisibly -- the same values rendered on its `Done` line
#'   (`"running"` resolves to `"success"`, as it does for display). `NULL`,
#'   invisibly, if there was no open step to close.
#' @seealso [log_open()]
#' @export
#' @examples
#' logtree_reset()
#' log_open("Step 1")
#' log_info("a child line")
#' log_close()
#'
#' logtree_reset()
#' log_open("Step 2")
#' log_error("failed once")
#' log_close(status = "success")  # recovered: override the elevated glyph
#'
#' logtree_reset()
#' log_open("Step 3")
#' result <- log_close()  # result$status, result$elapsed
log_close <- function(id = NULL, status = NULL) {
  if (is.null(id)) {
    cur <- nearest_open_step()
    if (is.null(cur)) return(invisible(NULL))
    id <- cur$id
  }
  if (!is.null(status)) {
    if (!status %in% c("success", "warning", "error")) {
      stop('`status` must be one of "success", "warning", "error".', call. = FALSE)
    }
    set_stack_entry_status(id, status)
  }
  close_step(id)
}

# -- Formatting: corner-on-close, zero-buffer (design doc section 3.5) --
#
# Every printed line is <rails><connector> <glyph> <msg>. A tree "column"
# is as wide as the connector glyph plus its trailing space (e.g. the
# unicode branch connector plus space is 3 columns wide), and the rail
# unit for an *open* ancestor pads the pipe glyph out to that same width
# so verticals line up under the connector above them.
#
# The single space between the glyph and the message is itself themeable
# (`glyph_gap`), so every formatter below spaces that column through
# glyph_pad() rather than a hard-coded " ".
#
# These functions are pure (theme/color passed in, string returned) so the
# same layout math backs every sink: the console sink uses the active
# theme with color, the plain-text file sink always uses the ascii theme
# with no ANSI codes (design doc section 6).

tree_col_width <- function(theme = the$theme) {
  nchar(theme$branch$glyph) + theme_col_gap(theme)
}

# --- Wrapping (logtree_theme(wrap = )) --------------------------------------
#
# A long message used to run straight off the right edge of the terminal. With
# a wrap width set, it is word-wrapped instead and its continuation lines are
# indented to the message column, with the rails carried down so the tree
# stays readable.
#
# Formatters keep returning ONE string, now possibly containing embedded
# newlines. That is what lets every sink stay untouched: console_sink() and
# both file sinks already cat() whatever they are handed.

# Greedy word wrap of `msg` to `width` display columns, one element per line.
# A width below 1 -- a tree deeper than the terminal is wide -- degrades to no
# wrapping at all, which is far more usable than a one-column line.
wrap_message <- function(msg, width) {
  if (is.na(width) || width < 1L) return(msg)
  if (cli::ansi_nchar(msg, type = "width") <= width) return(msg)
  lines <- cli::ansi_strwrap(msg, width = width)
  if (length(lines) == 0L) return(msg)
  unlist(lapply(lines, hard_wrap, width = width), use.names = FALSE)
}

# Break a token that has no space to break at and is still wider than the
# column -- a long path, a URL, a stack frame. Walks display widths rather than
# characters so a wide (CJK / emoji) cell cannot straddle the edge. Styling is
# dropped from such a token, since splitting inside an ANSI run is not safe;
# that only affects messages the caller styled itself, and only the overlong
# ones.
hard_wrap <- function(x, width) {
  if (cli::ansi_nchar(x, type = "width") <= width) return(x)
  chars <- strsplit(cli::ansi_strip(x), "", fixed = TRUE)[[1L]]
  widths <- nchar(chars, type = "width")
  out   <- character(0)
  start <- 1L
  used  <- 0L
  for (i in seq_along(chars)) {
    if (used + widths[[i]] > width && i > start) {
      out   <- c(out, paste(chars[start:(i - 1L)], collapse = ""))
      start <- i
      used  <- 0L
    }
    used <- used + widths[[i]]
  }
  c(out, paste(chars[start:length(chars)], collapse = ""))
}

# Assemble one rendered line from a fully-rendered `head` (rails + connector +
# glyph + gap) and its message.
#
# `cols` is the head's display width. It is computed by the caller from depth
# and the theme's declared glyph widths, never measured: ansi_nchar() cannot
# size an emoji cell, which is the very reason each glyph declares its own
# `width` (design doc section 4.2).
#
# `cont` is the head that continuation lines get -- the same rails, with the
# connector and glyph columns blanked -- so wrapped text lines up under the
# first line's message rather than restarting at the left margin.
#
# `cols` and `cont` are deliberately touched only *after* the no-wrap return,
# so callers can pass them as unevaluated expressions and R's lazy arguments
# keep them from ever being computed on the default path. `cont` costs a
# rail_unit(), and that costs a cli::combine_ansi_styles() -- about a sixth of
# the time it takes to render a line. Callers must therefore pass the
# expressions inline rather than assigning them to locals first.
compose_line <- function(head, msg, cols, cont, theme = the$theme) {
  width <- theme_wrap_width(theme)
  if (is.na(width)) return(paste0(head, msg))
  parts <- wrap_message(msg, width - cols)
  if (length(parts) < 2L) return(paste0(head, msg))
  paste(c(paste0(head, parts[[1L]]), paste0(cont, parts[-1L])), collapse = "\n")
}

# `n` levels' worth of vertical rail, for an ancestor chain that is still open.
rails <- function(n, theme = the$theme, color = TRUE) {
  strrep(rail_unit(theme, color), max(n, 0L))
}

# Width of the glyph column plus the gap after it: what a continuation line
# must skip to land on the message column.
glyph_gutter <- function(theme = the$theme) {
  theme_slot_width(theme) + theme_glyph_gap(theme)
}

# A line that carries a status glyph but no position in the tree: the
# logtree_summary() digest entries and the with_logging() run-summary line.
# Same message column and same wrapping as a tree line, minus the rails.
compose_flat_line <- function(glyph, msg, theme = the$theme) {
  gutter <- glyph_gutter(theme)
  compose_line(paste0(glyph, glyph_pad(theme)), msg, gutter,
               strrep(" ", gutter), theme)
}

rail_unit <- function(theme = the$theme, color = TRUE) {
  w <- tree_col_width(theme)
  pipe_glyph <- theme$pipe$glyph
  raw <- paste0(pipe_glyph, strrep(" ", max(w - nchar(pipe_glyph), 0L)))
  colorize(raw, theme$pipe$color, color)
}

connector_str <- function(key, theme = the$theme, color = TRUE) {
  paste0(theme_connector(key, theme, color), strrep(" ", theme_col_gap(theme)))
}

# Like connector_str(), but spaced by `connector_gap` instead of `col_gap`.
# Used only where a line's own connector sits immediately before its status
# glyph -- a leaf or a step's close line -- never on a step's *open* line
# (format_open, format_group_header), which keeps rendering flush at any
# `compact` density: `connector_gap` widens the glyph's own approach, not
# every rail column down the tree.
own_connector_str <- function(key, theme = the$theme, color = TRUE) {
  paste0(theme_connector(key, theme, color), strrep(" ", theme_connector_gap(theme)))
}

# Display width of a line's own branch/corner connector plus the gap after
# it -- `connector_gap` rather than `col_gap`, so this column can widen
# independently of the ancestor rail columns above it (rails() / tree_col_width()).
# Every built-in preset's branch and corner glyphs are the same width, so the
# caller's `key` only matters when a hand-built theme's diverge.
own_connector_width <- function(key, theme = the$theme) {
  nchar(theme[[key]]$glyph) + theme_connector_gap(theme)
}

# A pipe rail, padded out to `own_connector_width()` rather than
# `tree_col_width()`: the segment an *open* line's own column collapses to
# on its wrapped continuation rows, where more siblings may still follow
# (see rail_unit(), its ancestor-column counterpart).
own_rail <- function(key, theme = the$theme, color = TRUE) {
  w <- own_connector_width(key, theme)
  pipe_glyph <- theme$pipe$glyph
  raw <- paste0(pipe_glyph, strrep(" ", max(w - nchar(pipe_glyph), 0L)))
  colorize(raw, theme$pipe$color, color)
}

# A pipe rail padded out to the glyph column's own width: the segment an
# *open* line's glyph column collapses to on its wrapped continuation rows.
# An open line's glyph sits at exactly the column its children's connectors
# take, so the rail runs from the wrapped label straight down into the first
# child -- and, failing children, into the step's own close line, which is
# always there. Leaf and close lines never use it: nothing nests under them.
# A group header passes its own marker width for `w`, that column being where
# the group's members hang.
glyph_rail <- function(theme = the$theme, color = TRUE, w = glyph_gutter(theme)) {
  pipe_glyph <- theme$pipe$glyph
  raw <- paste0(pipe_glyph, strrep(" ", max(w - nchar(pipe_glyph), 0L)))
  colorize(raw, theme$pipe$color, color)
}

pad_custom_glyph <- function(glyph, theme = the$theme) {
  w <- theme_slot_width(theme)
  paste0(glyph, strrep(" ", max(w - 1L, 0L)))
}

format_open <- function(entry, theme = the$theme, color = TRUE) {
  d <- entry$depth
  # An opening line sits one level shallower than its own children, so its
  # continuation carries the rails down to d - 1: after a branch connector the
  # vertical rail continues, since more siblings may still follow. Its own
  # glyph column rails too (glyph_rail), since that is where its children
  # hang -- which is also the only rail a depth-1 root has to give.
  prefix <- if (d == 1L) "" else {
    paste0(rails(d - 2L, theme, color), connector_str("branch", theme, color))
  }
  glyph <- if (is.null(entry$glyph)) theme_glyph("step", theme, color) else pad_custom_glyph(entry$glyph, theme)
  # cols/cont are passed inline, unevaluated -- see compose_line().
  compose_line(
    paste0(prefix, glyph, glyph_pad(theme)), entry$label,
    cols = max(d - 1L, 0L) * tree_col_width(theme) + glyph_gutter(theme),
    cont = paste0(if (d == 1L) "" else rails(d - 1L, theme, color),
                  glyph_rail(theme, color)),
    theme = theme
  )
}

# The word a close line prints before its elapsed time. Read from the closing
# status's own slot, falling back to the `done` slot's `text` and finally to
# the built-in "Done" -- so a theme can rename every close line at once
# (`done = list(text = "Complete")`) or only the ones that went wrong
# (`error = list(text = "Failed")`). close_glyph_key() already maps a clean
# close onto `done`, which is why `success` carries no `text` of its own.
close_text_template <- function(status, theme = the$theme) {
  key <- close_glyph_key(status, theme)
  theme_field(key, "text", theme_field("done", "text", "Done", theme), theme)
}

# Expand a close-line template: `{label}` is the closing step's own label --
# a group's name, for a group close, since groups carry `name` and no `label`
# -- and `{elapsed}` the already-formatted time.
expand_close_text <- function(template, entry, elapsed) {
  # Fast path, and it is the common one: every built-in template is a plain
  # word, and this runs on every close line. A fixed-string grepl costs a
  # tenth of the gregexpr() below, so the scan is worth skipping outright.
  if (!grepl("{", template, fixed = TRUE)) return(template)
  label <- if (!is.null(entry$label)) entry$label else entry$name
  # An entry carrying neither (a hand-assembled one, or a future entry kind)
  # expands to the empty string; a NULL replacement is not substitutable.
  if (is.null(label)) label <- ""
  m    <- gregexpr("\\{label\\}|\\{elapsed\\}", template)
  hits <- regmatches(template, m)[[1L]]
  if (length(hits) == 0L) return(template)
  # One pass, via regmatches<-, rather than a gsub() per placeholder: a value
  # that happens to contain a placeholder -- a step literally labelled
  # "{elapsed}" -- is then inserted as data instead of being rescanned and
  # substituted again. A label is user data, never part of the template.
  regmatches(template, m) <- list(ifelse(hits == "{label}", label, elapsed))
  template
}

# The elapsed-time column of a close line, governed by the theme's `elapsed`
# slot: `show = FALSE` drops it outright, `min` hides anything faster than a
# threshold (which is how you silence the "0.00s" noise on trivial steps), and
# `slow` / `slow_color` restyle the ones worth noticing. Returns "" when the
# time is hidden, so callers join their columns conditionally.
#
# `gate = FALSE` keeps the styling but skips the hiding rules. The
# with_logging() run-summary line uses it: that line reads "Run complete in
# <time>", so suppressing the time would leave a dangling sentence.
format_elapsed_field <- function(seconds, theme = the$theme, color = TRUE,
                                 gate = TRUE) {
  if (gate) {
    if (!isTRUE(theme_field("elapsed", "show", TRUE, theme))) return("")
    min <- theme_field("elapsed", "min", 0, theme)
    if (is.numeric(min) && length(min) == 1L && !is.na(min) && seconds < min) {
      return("")
    }
  }
  col  <- theme_field("elapsed", "color", NULL, theme)
  slow <- theme_field("elapsed", "slow", NULL, theme)
  if (is.numeric(slow) && length(slow) == 1L && !is.na(slow) && seconds >= slow) {
    col <- theme_field("elapsed", "slow_color", NULL, theme)
  }
  colorize(format_elapsed(seconds), col, color)
}

# A close line's message: the themed word, then the elapsed time. Either side
# can be empty -- `text = ""` drops the word, and the `elapsed` slot can hide
# the time -- so the two-space separator is placed only when there is
# something on both sides of it.
close_message <- function(entry, status, theme = the$theme, color = TRUE) {
  template <- close_text_template(status, theme)
  elapsed  <- format_elapsed_field(entry$elapsed, theme, color)
  text     <- expand_close_text(template, entry, elapsed)
  # A template that places {elapsed} itself owns that column; don't print the
  # time a second time after it.
  if (grepl("{elapsed}", template, fixed = TRUE)) return(text)
  if (!nzchar(text)) return(elapsed)
  if (!nzchar(elapsed)) return(text)
  paste0(text, "  ", elapsed)
}

format_close <- function(entry, theme = the$theme, color = TRUE) {
  d      <- entry$depth
  tcw    <- tree_col_width(theme)
  base   <- rails(d - 1L, theme, color)
  prefix <- paste0(base, own_connector_str("corner", theme, color))
  status <- resolved_status(entry$status)
  glyph  <- theme_glyph(close_glyph_key(status, theme), theme, color)
  msg    <- close_message(entry, status, theme, color)
  # A theme that drops both the word and the time leaves a glyph-only close
  # line; skip the gap too rather than trailing a space off the end of it.
  if (!nzchar(msg)) return(paste0(prefix, glyph))
  # Nothing follows a corner at its own column, so the continuation blanks that
  # column out instead of carrying a rail down it.
  # cols/cont are passed inline, unevaluated -- see compose_line().
  compose_line(
    paste0(prefix, glyph, glyph_pad(theme)), msg,
    cols = (d - 1L) * tcw + own_connector_width("corner", theme) + glyph_gutter(theme),
    cont = paste0(base, strrep(" ", own_connector_width("corner", theme)),
                  strrep(" ", glyph_gutter(theme))),
    theme = theme
  )
}

format_leaf <- function(status, msg, depth, theme = the$theme, color = TRUE,
                        corner = FALSE) {
  # A `corner = TRUE` leaf is the terminal line of its section (the `close =`
  # force-close): it takes the corner connector instead of branch, standing in
  # for the suppressed close line -- and, like a close line, nothing follows it
  # at that column, so its continuation blanks the column rather than railing it.
  tcw  <- tree_col_width(theme)
  # `base` is needed for the prefix either way, so computing it here costs
  # nothing extra; the corner branch reuses it for the continuation too.
  base <- if (depth == 0L) "" else rails(depth - 1L, theme, color)
  own_key <- if (isTRUE(corner)) "corner" else "branch"
  prefix <- if (depth == 0L) "" else paste0(base, own_connector_str(own_key, theme, color))
  # cols/cont are passed inline, unevaluated -- see compose_line().
  compose_line(
    paste0(prefix, theme_glyph(status, theme, color), glyph_pad(theme)), msg,
    cols = if (depth == 0L) glyph_gutter(theme) else {
      (depth - 1L) * tcw + own_connector_width(own_key, theme) + glyph_gutter(theme)
    },
    cont = paste0(
      if (depth == 0L) "" else if (isTRUE(corner)) {
        paste0(base, strrep(" ", own_connector_width("corner", theme)))
      } else {
        paste0(base, own_rail("branch", theme, color))
      },
      strrep(" ", glyph_gutter(theme))
    ),
    theme = theme
  )
}

format_group_header <- function(entry, theme = the$theme, color = TRUE) {
  d <- entry$depth
  prefix <- if (d == 1L) "" else {
    paste0(rails(d - 2L, theme, color), connector_str("branch", theme, color))
  }
  g     <- theme$group
  has   <- !is.null(g$glyph) && nzchar(g$glyph)
  mark  <- if (has) paste0(g$glyph, glyph_pad(theme)) else ""
  col   <- if (is.null(g)) "cyan" else g$color
  label <- if (isTRUE(g$bracket)) paste0("< ", entry$name, " >") else entry$name
  # A group's marker is not a status glyph -- it carries no declared `width`,
  # so its column is the marker plus the gap, not glyph_gutter().
  # The marker and the name are coloured as one run, so the header reads as a
  # single object rather than a glyph next to some text.
  #
  # This formatter cannot use compose_line(): a group's marker is not a status
  # glyph, so its column is the marker plus the gap rather than glyph_gutter().
  # It returns before computing the continuation for the same reason
  # compose_line() defers -- rails() is the expensive part of rendering a line.
  width <- theme_wrap_width(theme)
  if (is.na(width)) {
    return(paste0(prefix, colorize(paste0(mark, label), col, color)))
  }
  gutter <- if (has) nchar(g$glyph) + theme_glyph_gap(theme) else 0L
  cols   <- max(d - 1L, 0L) * tree_col_width(theme) + gutter
  parts  <- wrap_message(label, width - cols)
  first  <- paste0(prefix, colorize(paste0(mark, parts[[1L]]), col, color))
  if (length(parts) < 2L) return(first)
  # The marker column rails on the continuation for the same reason a step's
  # glyph column does: the group's members hang from it. A theme with no
  # marker at all (`group = list(glyph = "")`) has no column to spare -- the
  # name itself starts where the members' connectors will -- so it stays blank.
  cont <- if (d == 1L) "" else rails(d - 1L, theme, color)
  mark_cont <- if (gutter > 0L) glyph_rail(theme, color, gutter) else ""
  rest <- paste0(cont, mark_cont, colorize(parts[-1L], col, color))
  paste(c(first, rest), collapse = "\n")
}
