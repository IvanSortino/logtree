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
# These functions are pure (theme/color passed in, string returned) so the
# same layout math backs every sink: the console sink uses the active
# theme with color, the plain-text file sink always uses the ascii theme
# with no ANSI codes (design doc section 6).

tree_col_width <- function(theme = the$theme) {
  nchar(theme$branch$glyph) + 1L
}

rail_unit <- function(theme = the$theme, color = TRUE) {
  w <- tree_col_width(theme)
  pipe_glyph <- theme$pipe$glyph
  raw <- paste0(pipe_glyph, strrep(" ", max(w - nchar(pipe_glyph), 0L)))
  colorize(raw, theme$pipe$color, color)
}

connector_str <- function(key, theme = the$theme, color = TRUE) {
  paste0(theme_connector(key, theme, color), " ")
}

pad_custom_glyph <- function(glyph, theme = the$theme) {
  w <- theme_slot_width(theme)
  paste0(glyph, strrep(" ", max(w - 1L, 0L)))
}

format_open <- function(entry, theme = the$theme, color = TRUE) {
  d <- entry$depth
  prefix <- if (d == 1L) {
    ""
  } else {
    paste0(strrep(rail_unit(theme, color), max(d - 2L, 0L)), connector_str("branch", theme, color))
  }
  glyph <- if (is.null(entry$glyph)) theme_glyph("step", theme, color) else pad_custom_glyph(entry$glyph, theme)
  paste0(prefix, glyph, " ", entry$label)
}

format_close <- function(entry, theme = the$theme, color = TRUE) {
  d <- entry$depth
  prefix <- paste0(strrep(rail_unit(theme, color), max(d - 1L, 0L)), connector_str("corner", theme, color))
  status <- resolved_status(entry$status)
  paste0(prefix, theme_glyph(status, theme, color), " Done  ", format_elapsed(entry$elapsed))
}

format_leaf <- function(status, msg, depth, theme = the$theme, color = TRUE,
                        corner = FALSE) {
  # A `corner = TRUE` leaf is the terminal line of its section (the `close =`
  # force-close): it takes the corner connector instead of branch, standing in
  # for the suppressed close line.
  connector <- if (isTRUE(corner)) "corner" else "branch"
  prefix <- if (depth == 0L) {
    ""
  } else {
    paste0(strrep(rail_unit(theme, color), max(depth - 1L, 0L)), connector_str(connector, theme, color))
  }
  paste0(prefix, theme_glyph(status, theme, color), " ", msg)
}

format_group_header <- function(entry, theme = the$theme, color = TRUE) {
  d <- entry$depth
  prefix <- if (d == 1L) {
    ""
  } else {
    paste0(strrep(rail_unit(theme, color), max(d - 2L, 0L)), connector_str("branch", theme, color))
  }
  g     <- theme$group
  mark  <- if (!is.null(g$glyph) && nzchar(g$glyph)) paste0(g$glyph, " ") else ""
  col   <- if (is.null(g)) "cyan" else g$color
  label <- if (isTRUE(g$bracket)) paste0("< ", entry$name, " >") else entry$name
  paste0(prefix, colorize(paste0(mark, label), col, color))
}
