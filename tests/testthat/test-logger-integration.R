test_that("layout_logtree maps every logger severity onto the right logtree leaf", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()
  logtree_threshold("debug")

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

test_that("logtree_logger() wires logger to render as logtree leaves", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()
  logtree_threshold("debug")

  ns <- "logtree_logger_test"
  withr::defer({
    logger::log_layout(logger::layout_simple, namespace = ns)
    logger::log_appender(logger::appender_console, namespace = ns)
    logger::log_threshold(logger::INFO, namespace = ns)
  })

  logtree_logger(namespace = ns)

  f <- function() {
    log_step("Step")
    logger::log_info("connecting", namespace = ns)
    logger::log_debug("debug detail", namespace = ns)  # reaches logtree only because threshold opened
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^\\|- i connecting$", out)))
  expect_true(any(grepl("^\\|- d debug detail$", out)))
})

test_that("logtree_logger(threshold = FALSE) leaves logger's own gate in place", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()
  logtree_threshold("debug")

  ns <- "logtree_logger_gate_test"
  withr::defer({
    logger::log_layout(logger::layout_simple, namespace = ns)
    logger::log_appender(logger::appender_console, namespace = ns)
    logger::log_threshold(logger::INFO, namespace = ns)
  })

  logger::log_threshold(logger::WARN, namespace = ns)
  logtree_logger(namespace = ns, threshold = FALSE)

  f <- function() {
    log_step("Step")
    logger::log_info("suppressed by logger", namespace = ns)  # INFO < WARN, gated before layout
    logger::log_warn("passes logger gate", namespace = ns)
  }
  out <- capture.output(invisible(f()))

  expect_false(any(grepl("suppressed by logger", out)))
  expect_true(any(grepl("^\\|- ! passes logger gate$", out)))
})

test_that("logtree_logger() returns NULL invisibly", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())

  ns <- "logtree_logger_ret_test"
  withr::defer({
    logger::log_layout(logger::layout_simple, namespace = ns)
    logger::log_appender(logger::appender_console, namespace = ns)
    logger::log_threshold(logger::INFO, namespace = ns)
  })

  result <- withVisible(logtree_logger(namespace = ns))
  expect_null(result$value)
  expect_false(result$visible)
})
