the <- new.env(parent = emptyenv())
the$stack   <- list()
the$next_id <- 1L
the$summary <- list()

# Sink bookkeeping (R/sinks.R). `sinks` itself is a named list set up by
# .onLoad; these are the counters and side tables that go with it.
the$next_sink_id <- 1L
the$sink_stores  <- list()

# Which registered sinks asked for the call-site column in their own right
# (logtree_sink_file(trace = )). Capture is gated on the theme's `trace` slot,
# but a sink can want a trace the console is not showing -- a quiet terminal and
# a log file that records call sites -- so trace_enabled() (R/trace.R) ORs this
# in. A set of sink ids rather than a count, so logtree_sink_remove() can take
# back exactly the capture its sink asked for. Like `sinks` itself it is
# deliberately not cleared by logtree_reset().
the$trace_sinks <- character(0)

# Sinks that have already thrown once, so the warning emit() raises about a
# broken sink is not repeated on every subsequent event. Unlike `sinks` this
# *is* cleared by logtree_reset(): it is noise suppression, not configuration.
the$sink_failed <- character(0)

# Identifies one run in structured output: every record a "json" sink writes
# carries it, so the lines belonging to a single run can be picked out of a log
# file that many runs appended to. Set at load, and refreshed at each boundary
# where a new run plainly starts -- a with_logging() call, or a logtree_reset().
#
# Built from the wall clock and the process id rather than drawn at random, on
# purpose: sampling would consume the user's RNG stream, and a logger has no
# business perturbing a reproducible script's random numbers.
new_run_id <- function() {
  sprintf("%s-%d", format(wall_clock(), "%Y%m%dT%H%M%OS3"), Sys.getpid())
}

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

# Wall-clock time, as opposed to now()'s monotonic-ish process clock. The two
# answer different questions and neither substitutes for the other: now() times
# how long a step took, wall_clock() says when it happened. Its own function so
# that tests can freeze it the same way they freeze now().
wall_clock <- function() {
  Sys.time()
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
#' Registered sinks are deliberately *not* cleared: they are configuration
#' rather than run state, so a file sink set up once keeps recording across
#' resets. Take one off with [logtree_sink_remove()].
#'
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_reset()
logtree_reset <- function() {
  the$stack       <- list()
  the$next_id     <- 1L
  the$summary     <- list()
  the$sink_failed <- character(0)
  the$run_id      <- new_run_id()
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
