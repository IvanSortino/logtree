test_that("format_elapsed renders a mocked clock's elapsed time exactly", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  freeze_clock(c(0, 0.42))

  f <- function() {
    log_step("x")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "0\\.42s$")
})
