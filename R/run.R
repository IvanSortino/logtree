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
#' Wrap a script or pipeline's top-level call in `with_logging()` so an
#' uncaught error leaves a clean, correctly-colored tree instead of dimmed
#' "incomplete" steps. On error, every currently open step is marked
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
