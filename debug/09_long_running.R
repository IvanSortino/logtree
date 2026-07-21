devtools::load_all()

# Elapsed time formatting past the 1-minute and 1-hour marks.
#
# format_elapsed() (R/state.R) renders plain "%.2fs" under a minute, "Xm" /
# "Xm YYs" once minutes are involved, and "Xh" / "Xh YYm" once hours are
# involved (seconds are dropped once minutes appear, minutes are dropped
# once hours appear). This script fakes now() so the demo is instant instead
# of actually waiting an hour+; format_elapsed() is a pure function of the
# elapsed seconds, so the rendered output is identical to a real long wait.

fake_now <- local({
  times <- c(
    0,        # run start
    0,        # "Short step" open
    3.2,      # "Short step" close (3.20s)
    3.2,      # "Long export" open
    97.8,     # "Long export" close (94.60s -> "1m 35s")
    97.8,     # "Very long backfill" open
    3960,     # "Very long backfill" close (3862.2s -> "1h 04m")
    3960      # run end
  )
  i <- 0
  function() {
    i <<- i + 1
    times[[min(i, length(times))]]
  }
})
assignInNamespace("now", fake_now, ns = "logtree")

logtree_reset()
with_logging({
  log_step("Short step")
  log_close()

  log_step("Long export")
  log_info("streaming rows")
  log_close()

  log_step("Very long backfill")
  log_info("rewriting partitions")
  log_close()
})
