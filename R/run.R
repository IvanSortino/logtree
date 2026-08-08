mark_open_steps <- function(status) {
  for (i in seq_along(the$stack)) {
    if (!identical(the$stack[[i]]$kind, "step")) next  # groups carry no status
    if (status_severity(status) > status_severity(the$stack[[i]]$status)) {
      the$stack[[i]]$status <- status
    }
  }
  invisible(NULL)
}

print_run_summary <- function(status, elapsed) {
  # Output nobody asked for, so muting takes it -- unlike logtree_summary(),
  # which prints because it was called (R/state.R).
  if (isTRUE(the$muted)) return(invisible(NULL))
  label <- if (identical(status, "error")) "Run failed" else "Run complete"
  # gate = FALSE: this line reads "Run complete in <time>", so it takes the
  # `elapsed` slot's colouring but never its hiding rules -- a suppressed time
  # would leave the sentence hanging.
  # Stamped like any other live line: this one is printed as the run ends, so
  # "now" is the truth about it. The logtree_summary() digest is the opposite
  # case and carries no stamp -- it replays events that happened earlier.
  cat(compose_flat_line(
        theme_glyph(status),
        paste0(label, " in ", format_elapsed_field(elapsed, gate = FALSE)),
        stamp = wall_clock()
      ), "\n", sep = "")
}

# The action run by the global (top-level) error handler installed via
# with_logging(global = TRUE). Factored out of install_global_logging() so it
# is unit-testable without a real uncaught error. The stack-empty guard makes
# unrelated top-level/REPL errors (no open logtree steps) a no-op, so the
# persistent handler never prints stray leaf lines.
global_error_action <- function(cnd, summary) {
  if (length(the$stack) == 0L) return(invisible(NULL))
  mark_open_steps("error")
  # log_error_at(), not log_error(): we are inside a handler frame, so the usual
  # frame walk would trace this leaf to the handler. conditionCall() names the
  # call that threw instead (R/leaves.R).
  log_error_at(conditionMessage(cnd), conditionCall(cnd))
  if (summary) print_run_summary("error", now() - the$global_start)
  invisible(NULL)
}

# Install the session-persistent global calling handler for
# with_logging(global = TRUE). Idempotent; snapshots any prior global handlers
# (restored by logtree_reset()).
#
# The establish is deliberately UNGUARDED: globalCallingHandlers(error = ) errors
# ("should not be called with handlers on the stack") if any condition handler is
# active, and that call *cannot* be wrapped in tryCatch() to soften it -- the
# wrapper is itself a handler and would block the establish even at a clean top
# level. So global = TRUE must be called from a clean top level (the first line of
# a script); calling it where handlers are active (inside tryCatch(), or a
# function running under one) surfaces R's native error, by design. The no-arg
# query form used for the snapshot is always safe.
install_global_logging <- function(summary) {
  if (isTRUE(the$global_installed)) return(invisible(NULL))
  the$run_id <- new_run_id()
  prev <- globalCallingHandlers()
  globalCallingHandlers(error = function(cnd) global_error_action(cnd, summary))
  the$global_installed <- TRUE
  the$global_prev      <- prev
  the$global_start     <- now()
  invisible(NULL)
}

#' Run an expression with top-level error handling and a run summary
#'
#' Wrap a script or pipeline's top-level call in `with_logging()` so an
#' uncaught error leaves a clean, correctly-colored tree instead of dimmed
#' "interrupted" steps. On error, every currently open step is marked
#' failed, the error is logged as a leaf line, then rethrown --
#' `with_logging()` never silently swallows errors. It also prints a
#' "Run complete" / "Run failed" summary line with elapsed time.
#'
#' Note: `expr` is lazily evaluated, so `log_step()` calls written inside
#' the `{ ... }` block close when the function *lexically enclosing* that
#' block returns -- not necessarily when `with_logging()` itself returns.
#' Use `with_logging({ ... })` as a function's entire body to keep these
#' in sync; if other code runs after the call in the same function, steps
#' opened inside the block stay open until that function returns.
#'
#' The `global = TRUE` form is meant for the top level of a script, where
#' there is no frame to wrap. It is not shown in the examples below because
#' it installs a session-persistent handler and is only meaningful for an
#' error that reaches top level:
#'
#' ```r
#' with_logging(global = TRUE)
#' log_open("Load data")
#' stop("EOF")   # marks the open step failed + logs "EOF" before R exits
#' ```
#'
#' @param expr Code to run. Omitted when `global = TRUE`.
#' @param summary Print an end-of-run summary line? Default `TRUE`. In global
#'   mode only the "Run failed" line is printed (on an uncaught error); there is
#'   no frame exit to hang a "Run complete" line on.
#' @param global If `TRUE`, do not wrap an expression; instead install a
#'   session-persistent global error handler for use at the *top level of a
#'   script*. On an error that reaches top level *unhandled* while logtree steps
#'   are open, it marks those steps failed and logs the error message as a leaf
#'   -- the same result as the block form, but without wrapping the body. It
#'   fires only for genuinely uncaught top-level errors (an inner `tryCatch()`
#'   that catches first pre-empts it) and only when steps are open. The handler
#'   persists until [logtree_reset()]. Must be called from a clean top level --
#'   the first line of a script: calling it where condition handlers are active
#'   (inside `tryCatch()`, or a function running under one) errors, by design.
#'   Requires R (>= 4.0).
#' @return In block mode, the value of `expr`, invisibly. In global mode,
#'   `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' with_logging({
#'   log_step("Step one")
#'   log_success("done")
#' })
with_logging <- function(expr, summary = TRUE, global = FALSE) {
  if (isTRUE(global)) {
    if (!missing(expr)) {
      stop("`global = TRUE` installs a persistent top-level handler and takes no `expr`; use one or the other.",
           call. = FALSE)
    }
    return(install_global_logging(summary))
  }
  # A new run: structured output gets a fresh id, so the records belonging to
  # this call can be told apart in a log file many runs have appended to.
  the$run_id <- new_run_id()
  run_start  <- now()
  result <- tryCatch(
    withCallingHandlers(
      expr,
      error = function(cnd) {
        mark_open_steps("error")
        # See global_error_action(): the call site that matters is the one that
        # threw, not this handler.
        log_error_at(conditionMessage(cnd), conditionCall(cnd))
      }
    ),
    error = function(cnd) {
      if (summary) print_run_summary("error", now() - run_start)
      stop(cnd)
    }
  )
  if (summary) print_run_summary("success", now() - run_start)
  invisible(result)
}
