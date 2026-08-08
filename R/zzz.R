.onLoad <- function(libname, pkgname) {
  the$theme     <- console_preset("unicode")
  the$verbosity <- "info"
  the$run_id    <- new_run_id()
  # Sinks are keyed by id, with the console sink under the reserved one so it
  # can be targeted by logtree_sink_remove() like any other (R/sinks.R).
  sinks <- list(list(fn = console_sink))
  names(sinks)  <- console_sink_id
  the$sinks     <- sinks
}
