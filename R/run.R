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
  label <- if (identical(status, "error")) "Run failed" else "Run complete"
  cat(theme_glyph(status), " ", label, " in ", format_elapsed(elapsed), "\n", sep = "")
}

#' Run an expression with top-level error handling and a run summary
#'
#' Wraps `expr` with a top-level handler for the case where a step's code
#' actually throws and the error propagates up (as opposed to
#' [log_warn()]/[log_error()] being called from code that itself returns
#' normally, which [log_step()]'s per-step "incomplete" handling already
#' covers with no setup). Before the stack unwinds, every currently-open
#' step is flagged as failed and the error is logged as a leaf line; the
#' error is then rethrown once logging completes -- `with_logging()` never
#' silently swallows errors.
#'
#' Note: because `expr` is an ordinary (lazily evaluated) argument,
#' `log_step()` calls written directly inside the `{ ... }` block close
#' when the function *lexically enclosing* that block returns -- not
#' necessarily when `with_logging()` itself returns. In the normal usage
#' shown below, where `with_logging({ ... })` is a function's entire body,
#' these coincide. If other code runs in the same function after the
#' `with_logging({ ... })` call, steps opened inside the block stay open
#' until that surrounding function itself returns.
#'
#' @param expr Code to run.
#' @param summary Print an end-of-run summary line? Default `TRUE`.
#' @return The value of `expr`, invisibly.
#' @export
#' @examples
#' logtree_reset()
#' with_logging({
#'   log_step("Step one")
#'   log_success("done")
#' })
with_logging <- function(expr, summary = TRUE) {
  run_start <- now()
  result <- tryCatch(
    withCallingHandlers(
      expr,
      error = function(cnd) {
        mark_open_steps("error")
        log_error(conditionMessage(cnd))
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
