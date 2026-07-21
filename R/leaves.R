status_severity <- function(status) {
  match(status, c("running", "success", "warning", "error"))
}

nearest_open_step <- function() {
  for (i in rev(seq_along(the$stack))) {
    if (identical(the$stack[[i]]$kind, "step")) return(the$stack[[i]])
  }
  NULL
}

elevate_current_step <- function(new_status) {
  # Skip synthetic group nodes -- elevation targets the nearest real step.
  current <- nearest_open_step()
  if (is.null(current)) return(invisible(NULL))
  if (status_severity(new_status) > status_severity(current$status)) {
    set_stack_entry_status(current$id, new_status)
  }
  invisible(NULL)
}

verbosity_rank      <- c(debug = 0L, info = 1L, warn = 2L, error = 3L)
leaf_verbosity_rank <- c(debug = 0L, info = 1L, success = 1L, warning = 2L, error = 3L)

should_emit_leaf <- function(status) {
  leaf_verbosity_rank[[status]] >= verbosity_rank[[the$verbosity]]
}

emit_leaf <- function(status, msg) {
  # A leaf at a group's level means that (member-less) group is done -- close
  # any lingering group before the leaf is placed or gated out.
  settle_groups()
  # Verbosity only gates whether this leaf line is rendered -- it never
  # affects elevate_current_step(), which callers run beforehand, so a
  # step's close glyph still reflects a suppressed warning/error.
  if (!should_emit_leaf(status)) return(invisible(NULL))
  id <- the$next_id
  the$next_id <- id + 1L
  emit(list(kind = "leaf", status = status, label = msg,
            depth = current_depth(), id = id, parent_id = current_parent_id()))
}

#' Log a debug leaf line
#'
#' The most verbose leaf level, for fine-grained diagnostic detail that
#' would be noisy at the default verbosity. Shown only when verbosity is
#' `"debug"` (see [logtree_threshold()]). Like [log_info()] and
#' [log_success()], it does not elevate the enclosing step's status --
#' unlike [log_warn()]/[log_error()].
#'
#' @param msg Character scalar.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' logtree_threshold("debug")
#' log_debug("Cache miss for key user:42")
#' logtree_threshold("info")
log_debug <- function(msg) {
  emit_leaf("debug", msg)
  invisible(NULL)
}
#' Log an informational leaf line
#'
#' @param msg Character scalar.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_info("Reading config.yml")
log_info <- function(msg) {
  emit_leaf("info", msg)
  invisible(NULL)
}

#' Log a success leaf line
#'
#' @param msg Character scalar.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_success("Validated 12 parameters")
log_success <- function(msg) {
  emit_leaf("success", msg)
  invisible(NULL)
}

#' Log a warning leaf line
#'
#' Also elevates the currently-open step's status to `"warning"` (unless it
#' is already `"error"`), so the step's close line renders the elevated
#' glyph even though the enclosing function returns normally.
#'
#' @param msg Character scalar.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_warn("Retry 1/3 due to timeout")
log_warn <- function(msg) {
  elevate_current_step("warning")
  emit_leaf("warning", msg)
  invisible(NULL)
}

#' Log an error leaf line
#'
#' Also elevates the currently-open step's status to `"error"`, so the
#' step's close line renders the elevated glyph even though the enclosing
#' function returns normally (see [with_logging()] for the case where the
#' step's code actually throws instead).
#'
#' @param msg Character scalar.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_error("model timeout after 30s")
log_error <- function(msg) {
  elevate_current_step("error")
  emit_leaf("error", msg)
  invisible(NULL)
}
