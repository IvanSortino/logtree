the <- new.env(parent = emptyenv())
the$stack   <- list()
the$next_id <- 1L

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
  invisible(NULL)
}
