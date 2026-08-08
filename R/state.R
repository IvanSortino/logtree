the <- new.env(parent = emptyenv())
the$stack   <- list()
the$next_id <- 1L
the$summary <- list()

# How many registered sinks asked for the call-site column in their own right
# (logtree_sink_file(trace = )). Capture is gated on the theme's `trace` slot,
# but a sink can want a trace the console is not showing -- a quiet terminal and
# a log file that records call sites -- so trace_enabled() (R/trace.R) ORs this
# in. A count rather than a flag because sinks stack; like `sinks` itself it is
# deliberately not cleared by logtree_reset(), and there is as yet no way to
# unregister a sink (see debug/feature-plan.md item 4).
the$trace_sinks <- 0L

# with_logging(global = TRUE) installs a session-persistent global calling
# handler. These track whether it is installed, the global handlers that were
# in force before (restored on reset), and when it was installed (for the
# "Run failed" elapsed time).
the$global_installed <- FALSE
the$global_prev      <- NULL
the$global_start     <- NA_real_

now <- function() {
  proc.time()[["elapsed"]]
}

format_elapsed <- function(seconds) {
  if (seconds < 60) {
    return(sprintf("%.2fs", seconds))
  }

  total_seconds <- round(seconds)
  hours   <- total_seconds %/% 3600
  minutes <- (total_seconds %% 3600) %/% 60
  secs    <- total_seconds %% 60

  if (hours > 0) {
    if (minutes == 0) return(sprintf("%dh", hours))
    return(sprintf("%dh %02dm", hours, minutes))
  }
  if (secs == 0) {
    return(sprintf("%dm", minutes))
  }
  sprintf("%dm %02ds", minutes, secs)
}

#' Reset internal logtree state
#'
#' Clears the open-step stack and resets the internal id counter. Mainly
#' useful for tests and interactive/knitr re-runs where a previous run may
#' have left the stack non-empty (e.g. after an uncaught error with no
#' `with_logging()` wrapper).
#'
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
logtree_reset <- function() {
  the$stack   <- list()
  the$next_id <- 1L
  the$summary <- list()
  # Tear down any global handler installed by with_logging(global = TRUE),
  # restoring whatever global handlers were in force beforehand. Guarded:
  # globalCallingHandlers() errors if condition handlers are on the stack
  # (e.g. reset called from inside a tryCatch), so if we cannot tear down now
  # we leave it installed for a later top-level reset rather than throwing.
  if (isTRUE(the$global_installed)) {
    cleared <- tryCatch({
      globalCallingHandlers(NULL)
      if (length(the$global_prev)) do.call(globalCallingHandlers, the$global_prev)
      TRUE
    }, error = function(e) FALSE)
    if (cleared) {
      the$global_installed <- FALSE
      the$global_prev      <- NULL
      the$global_start     <- NA_real_
    }
  }
  invisible(NULL)
}
