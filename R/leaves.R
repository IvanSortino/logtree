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

# Normalise a `threshold` argument to a level name, or NULL for "follow the
# global one". Unlike the theme's defensively-checked fields this is a function
# argument, so a typo is an error naming the valid levels rather than a silent
# fallback.
resolve_threshold <- function(threshold) {
  if (is.null(threshold)) return(NULL)
  if (!is.character(threshold) || length(threshold) != 1L || is.na(threshold)) {
    stop('`threshold` must be NULL or one of "debug", "info", "warn", "error".',
         call. = FALSE)
  }
  match.arg(tolower(threshold), c("debug", "info", "warn", "error"))
}

# The level a sink gates on: its own threshold when it has one, the global
# logtree_threshold() otherwise -- read afresh each time, so moving the global
# level still moves every sink that did not pin its own.
sink_threshold_rank <- function(threshold) {
  verbosity_rank[[if (is.null(threshold)) the$verbosity else threshold]]
}

sink_admits_leaf <- function(status, threshold) {
  leaf_verbosity_rank[[status]] >= sink_threshold_rank(threshold)
}

# Would this leaf reach *any* sink? Cheap: the registry is a handful of entries,
# and the alternative is rendering a line nobody is listening for. A muted run
# reaches none of them, which is what makes muting cheaper than it looks.
any_sink_admits <- function(status) {
  if (isTRUE(the$muted)) return(FALSE)
  for (sink in the$sinks) {
    if (sink_admits_leaf(status, sink$threshold)) return(TRUE)
  }
  FALSE
}

# Does anything at all want this leaf -- a sink, or the summary digest?
#
# Verbosity is a *rendering* gate: it decides what a sink prints, not what the
# run remembers. So a warning suppressed by logtree_threshold("error") still
# reaches the digest, exactly as it still elevates its step's close glyph. The
# check lives here rather than in emit() for one reason beyond tidiness: a leaf
# nobody wants must not pay for a call-site frame walk.
leaf_wanted <- function(status, summary) {
  summary_keeps(status, summary) || any_sink_admits(status)
}

# `trace` is supplied by the callers that already hold a call site --
# log_error_at() below, and layout_logtree() -- and NULL everywhere else.
#
# `capture = FALSE` goes with those callers, and is not the same thing as
# `trace = NULL`. They log from inside a frame of their own, so the frame walk
# below would name the handler or the layout rather than the user's code. Their
# call site can legitimately come out NULL -- a condition raised without a call,
# say -- and if that fell through to the walk we would print exactly the wrong
# answer instead of no answer. So the two are separate: `trace` is the value,
# `capture` is permission to go looking.
emit_leaf <- function(status, msg, close = FALSE, summary = NA, trace = NULL,
                      capture = TRUE) {
  # A leaf at a group's level means that (member-less) group is done -- close
  # any lingering group before the leaf is placed or gated out.
  settle_groups()
  # Verbosity only gates whether this leaf line is rendered -- it never
  # affects elevate_current_step(), which callers run beforehand, so a
  # step's close glyph still reflects a suppressed warning/error.
  #
  # The gate here is "does anything want this leaf at all", not "does the
  # console want it": each sink applies its own threshold inside emit(), so a
  # debug-level log file no longer forces debug onto the console.
  if (leaf_wanted(status, summary)) {
    # Capture inside the gate, not above it: a leaf nobody is listening for
    # then costs no frame walk at all.
    #
    # up = 2 because all five leaf wrappers below sit exactly one frame between
    # the user's function and here -- log_warn()/log_error() call
    # elevate_current_step() first, but that returns before we are entered, so it
    # does not shift the count. test-trace.R pins this constant; a future wrapper
    # at a different depth would silently mis-attribute every line.
    if (isTRUE(capture) && is.null(trace) && trace_enabled()) {
      this_call <- sys.call(-1L)
      trace     <- capture_trace(this_call, up = 2L)
    }
    id <- the$next_id
    the$next_id <- id + 1L
    # `terminal = TRUE` renders this leaf with the corner connector -- it is
    # the section's closing line (see close = below).
    emit(list(kind = "leaf", status = status, label = msg,
              depth = current_depth(), id = id, parent_id = current_parent_id(),
              terminal = isTRUE(close), summary = summary, trace = trace))
  }
  # The force-close is a structural request, independent of whether the leaf
  # line itself was verbosity-gated: close even if the line was suppressed.
  if (isTRUE(close)) close_current_section_silent()
  invisible(NULL)
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
#' @param close Logical. When `TRUE`, force-close the enclosing section after
#'   this line: the line is shown as the section's terminal (corner) line and
#'   its `Done` line is suppressed. Defaults to `FALSE`.
#' @param summary Whether to record this line in the [logtree_summary()]
#'   digest. `NA` (default) records it only when it is a warning or error;
#'   `TRUE` always records it; `FALSE` never does.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' logtree_threshold("debug")
#' log_debug("Cache miss for key user:42")
#' logtree_threshold("info")
log_debug <- function(msg, close = FALSE, summary = NA) {
  emit_leaf("debug", msg, close = close, summary = summary)
  invisible(NULL)
}
#' Log an informational leaf line
#'
#' @param msg Character scalar.
#' @param close Logical. When `TRUE`, force-close the enclosing section after
#'   this line: the line is shown as the section's terminal (corner) line and
#'   its `Done` line is suppressed. Defaults to `FALSE`.
#' @param summary Whether to record this line in the [logtree_summary()]
#'   digest. `NA` (default) records it only when it is a warning or error;
#'   `TRUE` always records it; `FALSE` never does.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_info("Reading config.yml")
log_info <- function(msg, close = FALSE, summary = NA) {
  emit_leaf("info", msg, close = close, summary = summary)
  invisible(NULL)
}

#' Log a success leaf line
#'
#' @param msg Character scalar.
#' @param close Logical. When `TRUE`, force-close the enclosing section after
#'   this line: the line is shown as the section's terminal (corner) line and
#'   its `Done` line is suppressed. Defaults to `FALSE`.
#' @param summary Whether to record this line in the [logtree_summary()]
#'   digest. `NA` (default) records it only when it is a warning or error;
#'   `TRUE` always records it; `FALSE` never does.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_success("Validated 12 parameters")
log_success <- function(msg, close = FALSE, summary = NA) {
  emit_leaf("success", msg, close = close, summary = summary)
  invisible(NULL)
}

#' Log a warning leaf line
#'
#' Also elevates the currently-open step's status to `"warning"` (unless it
#' is already `"error"`), so the step's close line renders the elevated
#' glyph even though the enclosing function returns normally.
#'
#' @param msg Character scalar.
#' @param close Logical. When `TRUE`, force-close the enclosing section after
#'   this line: the line is shown as the section's terminal (corner) line and
#'   its `Done` line is suppressed. Defaults to `FALSE`.
#' @param summary Whether to record this line in the [logtree_summary()]
#'   digest. `NA` (default) records it only when it is a warning or error;
#'   `TRUE` always records it; `FALSE` never does.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_warn("Retry 1/3 due to timeout")
log_warn <- function(msg, close = FALSE, summary = NA) {
  elevate_current_step("warning")
  emit_leaf("warning", msg, close = close, summary = summary)
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
#' @param close Logical. When `TRUE`, force-close the enclosing section after
#'   this line: the line is shown as the section's terminal (corner) line and
#'   its `Done` line is suppressed. Defaults to `FALSE`.
#' @param summary Whether to record this line in the [logtree_summary()]
#'   digest. `NA` (default) records it only when it is a warning or error;
#'   `TRUE` always records it; `FALSE` never does.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' log_error("model timeout after 30s")
log_error <- function(msg, close = FALSE, summary = NA) {
  elevate_current_step("error")
  emit_leaf("error", msg, close = close, summary = summary)
  invisible(NULL)
}

# log_error() for a condition caught by a handler.
#
# A handler logs from its own frame, so emit_leaf()'s frame walk would trace the
# leaf to the handler rather than to the code that threw -- the least useful
# answer available. conditionCall() carries the throwing call, so hand that in
# instead. `call` may be NULL (conditions raised without one), in which case the
# leaf simply carries no trace.
#
# Used by with_logging()'s calling handler and by global_error_action() (R/run.R).
log_error_at <- function(msg, call) {
  elevate_current_step("error")
  emit_leaf("error", msg, trace = trace_from_call(call), capture = FALSE)
  invisible(NULL)
}
