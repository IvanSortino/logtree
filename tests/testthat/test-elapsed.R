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

test_that("format_elapsed stays in seconds under a minute", {
  expect_equal(format_elapsed(0.42), "0.42s")
  expect_equal(format_elapsed(59.99), "59.99s")
})

test_that("format_elapsed converts to minutes at and past 60s", {
  expect_equal(format_elapsed(60), "1m")
  expect_equal(format_elapsed(65), "1m 05s")
  expect_equal(format_elapsed(125.4), "2m 05s")
  expect_equal(format_elapsed(3599), "59m 59s")
})

test_that("format_elapsed converts to hours at and past 3600s", {
  expect_equal(format_elapsed(3600), "1h")
  expect_equal(format_elapsed(3960), "1h 06m")
  expect_equal(format_elapsed(7200), "2h")
})
