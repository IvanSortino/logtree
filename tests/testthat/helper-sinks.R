# Scope sink registrations to the current test.
#
# Sinks survive logtree_reset() by design, so a test that registers one would
# otherwise leak it into every later test in the same session. Ordinary code
# takes a sink off with logtree_sink_remove(); this snapshots and restores the
# whole registry instead, so a test that *removes* the console sink is put back
# together too.
local_reset_sinks <- function(envir = parent.frame()) {
  sinks  <- the$sinks
  traces <- the$trace_sinks
  stores <- the$sink_stores
  withr::defer({
    the$sinks       <- sinks
    the$trace_sinks <- traces
    the$sink_stores <- stores
  }, envir = envir)
}
