test_that("layout_logtree maps every logger severity onto the right logtree leaf", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()
  logtree_set_verbosity("debug")

  f <- function() {
    log_step("Step")
    layout_logtree(logger::FATAL,   "fatal via logger")
    layout_logtree(logger::ERROR,   "error via logger")
    layout_logtree(logger::WARN,    "warn via logger")
    layout_logtree(logger::SUCCESS, "success via logger")
    layout_logtree(logger::INFO,    "info via logger")
    layout_logtree(logger::DEBUG,   "debug via logger")
    layout_logtree(logger::TRACE,   "trace via logger")
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^\\|- x fatal via logger$", out)))
  expect_true(any(grepl("^\\|- x error via logger$", out)))
  expect_true(any(grepl("^\\|- ! warn via logger$", out)))
  expect_true(any(grepl("^\\|- \\+ success via logger$", out)))
  expect_true(any(grepl("^\\|- i info via logger$", out)))
  expect_true(any(grepl("^\\|- d debug via logger$", out)))
  expect_true(any(grepl("^\\|- d trace via logger$", out)))
})

test_that("layout_logtree returns character(0) invisibly", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())

  result <- withVisible(layout_logtree(logger::INFO, "quiet"))
  expect_identical(result$value, character(0))
  expect_false(result$visible)
})

test_that("logger::log_info() routed through layout_logtree renders as a logtree leaf", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  ns <- "logtree_test"
  withr::defer({
    logger::log_layout(logger::layout_simple, namespace = ns)
    logger::log_appender(logger::appender_console, namespace = ns)
  })
  logger::log_layout(layout_logtree, namespace = ns)
  logger::log_appender(logger::appender_void, namespace = ns)

  f <- function() {
    log_step("Step")
    logger::log_info("hello from logger", namespace = ns)
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^\\|- i hello from logger$", out)))
})
