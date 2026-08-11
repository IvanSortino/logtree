# Scope a mute to the current test. Like sinks, the mute flag deliberately
# survives logtree_reset(), so it has to be put back by hand.
local_reset_mute <- function(envir = parent.frame()) {
  was <- isTRUE(the$muted)
  withr::defer(the$muted <- was, envir = envir)
}
