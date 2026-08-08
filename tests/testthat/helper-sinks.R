local_reset_sinks <- function(envir = parent.frame()) {
  withr::defer({
    the$sinks <- list(console_sink)
    # A sink registered with logtree_sink_file(trace = ) bumps this counter to
    # switch capture on; drop it with the sink, or trace capture leaks into every
    # later test in the session (the counter, like `sinks`, survives
    # logtree_reset() by design).
    the$trace_sinks <- 0L
  }, envir = envir)
}
