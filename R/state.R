the <- new.env(parent = emptyenv())
the$stack   <- list()
the$next_id <- 1L

now <- function() {
  proc.time()[["elapsed"]]
}

format_elapsed <- function(seconds) {
  sprintf("%.2fs", seconds)
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
