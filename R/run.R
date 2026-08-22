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

# --- Routing R's own conditions into the tree -------------------------------
#
# Tier-2 handling caught `error` only, so a warning() or message() raised by
# wrapped code went to stderr, outside the tree, while a log_warn() call
# rendered inside it. Same severity, two different places, and no way to read
# the run as one thing afterwards.
#
# with_logging(warnings = ) opts into routing them in. It is off by default and
# has to be, because routing means *muffling*: the condition becomes a leaf and
# stops there, so it no longer reaches warnings(), the caller's own handlers, or
# stderr. That is the right trade when the tree is meant to be the single record
# of a run, and the wrong one to make for somebody without asking.

condition_routes <- c("warning", "message")

# Normalise `warnings` to a character vector of the kinds to route. A function
# argument rather than a theme field, so a typo is an error naming the valid
# values instead of a silent fallback.
resolve_warnings <- function(x) {
  if (isFALSE(x)) return(character(0))
  if (isTRUE(x))  return(condition_routes)
  if (is.character(x) && length(x) > 0L && !anyNA(x) &&
      all(x %in% condition_routes)) {
    return(unique(x))
  }
  stop('`warnings` must be TRUE, FALSE, or a subset of c("warning", "message").',
       call. = FALSE)
}

# Route one condition into the tree as a leaf, then muffle it.
#
# Three guards, in this order:
#
#   * `the$routing` -- the leaf reaches every sink, and a sink that warns while
#     we are handling a warning would arrive straight back here. Re-entrancy is
#     dropped rather than recursed into; the second condition takes its ordinary
#     course instead.
#   * `guard` -- global mode only. With no logtree steps open there is no tree
#     for the condition to belong to, so warnings from unrelated code are left
#     alone. The same guard global_error_action() applies, for the same reason:
#     a session-persistent handler must not capture things it was not aimed at.
#   * findRestart() -- a condition signalled without the usual restart (a bare
#     signalCondition(), a custom condition class) must not turn into an error
#     about the missing restart.
#
# The trailing newline goes: message() conditions carry one, and it would put a
# blank row through the middle of the tree.
route_condition <- function(status, cnd, restart, guard = FALSE) {
  if (isTRUE(the$routing)) return(invisible(NULL))
  if (guard && length(the$stack) == 0L) return(invisible(NULL))
  the$routing <- TRUE
  on.exit(the$routing <- FALSE, add = TRUE)
  log_condition_at(status, sub("\n+$", "", conditionMessage(cnd)),
                   conditionCall(cnd))
  if (!is.null(findRestart(restart))) invokeRestart(restart)
  invisible(NULL)
}

route_warning <- function(cnd, guard = FALSE) {
  route_condition("warning", cnd, "muffleWarning", guard = guard)
}

route_message <- function(cnd, guard = FALSE) {
  route_condition("info", cnd, "muffleMessage", guard = guard)
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
install_global_logging <- function(summary, routes = character(0)) {
  if (isTRUE(the$global_installed)) return(invisible(NULL))
  the$run_id <- new_run_id()
  prev <- globalCallingHandlers()
  handlers <- list(error = function(cnd) global_error_action(cnd, summary))
  # guard = TRUE: a session-persistent handler must not swallow warnings from
  # code that has nothing to do with logtree, so routing only applies while
  # steps are open (see route_condition()).
  if ("warning" %in% routes) {
    handlers$warning <- function(cnd) route_warning(cnd, guard = TRUE)
  }
  if ("message" %in% routes) {
    handlers$message <- function(cnd) route_message(cnd, guard = TRUE)
  }
  do.call(globalCallingHandlers, handlers)
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
#' `warnings = TRUE` additionally routes R's *own* conditions into the tree:
#' a `warning()` raised by wrapped code becomes a [log_warn()] leaf and a
#' `message()` becomes a [log_info()] leaf, in place rather than on stderr, so
#' the tree is a complete record of the run rather than half of one. It is
#' opt-in because routing means **muffling** -- see the argument's own
#' documentation below for what that costs.
#'
#' @param expr Code to run. Omitted when `global = TRUE`.
#' @param warnings Route R's own conditions into the tree as leaf lines?
#'   `FALSE` (the default) leaves `warning()` and `message()` exactly as they
#'   are. `TRUE` routes both; a subset such as `"warning"` or `"message"` routes
#'   only those.
#'
#'   Two consequences to weigh before switching it on:
#'
#'   * **Routed conditions are muffled.** A routed `warning()` becomes a leaf
#'     and stops there: it no longer reaches `warnings()`, the caller's own
#'     handlers, or stderr. That is the point -- one record of the run rather
#'     than two halves -- but it means the tree is now the only place that
#'     warning appears.
#'   * **A routed warning elevates its step**, exactly as [log_warn()] does. So
#'     wrapping third-party code that warns freely will turn the enclosing steps
#'     yellow, which may be more honesty than you wanted.
#'
#'   In global mode the routing applies only while logtree steps are open, so a
#'   session-persistent handler cannot swallow warnings from unrelated code.
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
#'
#' # R's own conditions routed into the tree instead of onto stderr.
#' logtree_reset()
#' with_logging({
#'   log_step("Load data")
#'   warning("3 rows coerced to NA")
#'   message("using cached manifest")
#' }, warnings = TRUE)
with_logging <- function(expr, summary = TRUE, global = FALSE,
                         warnings = FALSE) {
  routes <- resolve_warnings(warnings)
  if (isTRUE(global)) {
    if (!missing(expr)) {
      stop("`global = TRUE` installs a persistent top-level handler and takes no `expr`; use one or the other.",
           call. = FALSE)
    }
    return(install_global_logging(summary, routes))
  }
  # A new run: structured output gets a fresh id, so the records belonging to
  # this call can be told apart in a log file many runs have appended to.
  the$run_id <- new_run_id()
  run_start  <- now()
  on_error <- function(cnd) {
    mark_open_steps("error")
    # See global_error_action(): the call site that matters is the one that
    # threw, not this handler.
    log_error_at(conditionMessage(cnd), conditionCall(cnd))
  }
  result <- tryCatch(
    # Two branches so the default path installs exactly the handler it always
    # did. `expr` is a promise and only the branch taken forces it.
    if (length(routes) == 0L) {
      withCallingHandlers(expr, error = on_error)
    } else {
      withCallingHandlers(
        expr,
        error   = on_error,
        warning = function(cnd) if ("warning" %in% routes) route_warning(cnd),
        message = function(cnd) if ("message" %in% routes) route_message(cnd)
      )
    },
    error = function(cnd) {
      if (summary) print_run_summary("error", now() - run_start)
      stop(cnd)
    }
  )
  if (summary) print_run_summary("success", now() - run_start)
  invisible(result)
}
