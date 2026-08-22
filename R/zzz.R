.onLoad <- function(libname, pkgname) {
  the$theme     <- console_preset("unicode")
  the$verbosity <- "info"
  the$run_id    <- new_run_id()
  # The option seeds the initial state only; logtree_mute()/logtree_unmute()
  # are in charge afterwards, the same split `the$verbosity` has.
  the$muted     <- isTRUE(getOption("logtree.silent", FALSE))
  # Sinks are keyed by id, with the console sink under the reserved one so it
  # can be targeted by logtree_sink_remove() like any other (R/sinks.R).
  sinks <- list(list(fn = console_sink))
  names(sinks)  <- console_sink_id
  the$sinks     <- sinks
}
