current_parent_id <- function() {
  n <- length(the$stack)
  if (n == 0L) return(0L)
  the$stack[[n]]$id
}

parse_group_by <- function(group_by) {
  if (length(group_by) != 1L) {
    stop("`group_by` must be a length-1 named vector, e.g. c(name = value).", call. = FALSE)
  }
  nm    <- names(group_by)
  value <- unname(group_by)
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
    depth     = length(the$stack) + 1L
  )
  the$stack[[length(the$stack) + 1L]] <- entry
  emit(list(kind = "group", entry = entry))
  id
}

push_step <- function(label, glyph = NULL, group_by = NULL) {
  if (is.null(group_by)) {
    settle_groups()
    parent_id <- current_parent_id()
  } else {
    g <- parse_group_by(group_by)
    parent_id <- open_or_reuse_group(g$name, g$value)
  }
  id <- the$next_id
  the$next_id <- id + 1L
  entry <- list(
    id        = id,
    parent_id = parent_id,
    kind      = "step",
    label     = label,
    start     = now(),
    depth     = length(the$stack) + 1L,
    status    = "running",
    glyph     = glyph
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

close_step <- function(id) {
  idx <- Find(function(i) the$stack[[i]]$id == id, seq_along(the$stack))
  if (is.null(idx)) return(invisible(NULL))
  # Cascade-close deepest-first down to (and including) idx. This keeps the
  # stack correct even if closing arrives out of the expected order (e.g. the
  # same-frame-sibling pattern in log_step("A"); log_step("B")).
  for (i in rev(seq(idx, length(the$stack)))) {
    entry <- the$stack[[i]]
    # Groups are header-only synthetic parents: pop silently, no close line.
    if (!identical(entry$kind, "group")) {
      entry$elapsed <- now() - entry$start
      emit(list(kind = "close", entry = entry))
    }
    the$stack[[i]] <- NULL
  }
  invisible(NULL)
}

finalize_step <- function(id, sentinel) {
  rv    <- returnValue(sentinel)
  entry <- find_stack_entry(id)
  if (!is.null(entry) && identical(rv, sentinel) && identical(entry$status, "running")) {
    # Abnormal (error-driven) exit with no with_logging() Tier-2 handler
    # having already elevated this step's status to "error" -- render as
    # incomplete/dimmed rather than a false success glyph.
    set_stack_entry_status(id, "incomplete")
  }
  close_step(id)
}

#' Open a logged step
#'
#' Prints an opening line for `msg` and registers an automatic close that
#' fires when the *calling* function's frame exits -- whether by normal
#' return, early `return()`, or an uncaught error propagating through it.
#' Because the close is registered in the caller's frame rather than inside
#' `log_step()` itself, nesting depth always stays in sync, even across
#' errors.
#'
#' @param msg Character scalar. The step's label.
#' @param glyph Optional character scalar overriding this step's glyph.
#' @param group_by Optional named length-1 vector `c(name = value)`. Adjacent
#'   `log_step()` calls sharing the same `value` are grouped under a single
#'   `< name >` header line. The value is the match key; the name is displayed.
#' @return The step's internal id, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' f <- function() {
#'   log_step("Doing work")
#' }
#' f()
log_step <- function(msg, glyph = NULL, group_by = NULL) {
  caller   <- rlang::caller_env()
  entry    <- push_step(msg, glyph, group_by = group_by)
  sentinel <- new.env(parent = emptyenv())
  withr::defer(finalize_step(entry$id, sentinel), envir = caller, priority = "first")
  invisible(entry$id)
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
  status <- if (identical(entry$status, "running")) "success" else entry$status
  paste0(prefix, theme_glyph(status, theme, color), " Done  ", format_elapsed(entry$elapsed))
}

format_leaf <- function(status, msg, depth, theme = the$theme, color = TRUE) {
  prefix <- if (depth == 0L) {
    ""
  } else {
    paste0(strrep(rail_unit(theme, color), max(depth - 1L, 0L)), connector_str("branch", theme, color))
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
  paste0(prefix, colorize(paste0("< ", entry$name, " >"), c("bold", "cyan"), color))
}
