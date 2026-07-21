test_that("default verbosity (info) shows info/success/warn/error leaf lines", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  f <- function() {
    log_step("Step")
    log_info("info line")
    log_success("success line")
    log_warn("warn line")
    log_error("error line")
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("info line", out)))
  expect_true(any(grepl("success line", out)))
  expect_true(any(grepl("warn line", out)))
  expect_true(any(grepl("error line", out)))
})

test_that("verbosity = warn hides info/success leaf lines but keeps warn/error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_set_verbosity("warn")

  f <- function() {
    log_step("Step")
    log_info("info line")
    log_success("success line")
    log_warn("warn line")
    log_error("error line")
  }
  out <- capture.output(invisible(f()))

  expect_false(any(grepl("info line", out)))
  expect_false(any(grepl("success line", out)))
  expect_true(any(grepl("warn line", out)))
  expect_true(any(grepl("error line", out)))
})

test_that("verbosity = error hides everything but error leaf lines", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_set_verbosity("error")

  f <- function() {
    log_step("Step")
    log_info("info line")
    log_warn("warn line")
    log_error("error line")
  }
  out <- capture.output(invisible(f()))

  expect_false(any(grepl("info line", out)))
  expect_false(any(grepl("warn line", out)))
  expect_true(any(grepl("error line", out)))
})

test_that("step open/close lines always render regardless of verbosity", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_set_verbosity("error")

  f <- function() {
    log_step("Always visible")
    log_info("hidden")
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^> Always visible$", out)))
  expect_true(any(grepl("Done", out)))
  expect_false(any(grepl("hidden", out)))
})

test_that("a suppressed log_warn still elevates the enclosing step's close glyph", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_set_verbosity("error")

  f <- function() {
    log_step("Step")
    log_warn("this text is suppressed")
  }
  out <- capture.output(invisible(f()))

  expect_false(any(grepl("this text is suppressed", out)))
  expect_match(out[length(out)], "^\\|- ! Done")
})

test_that("default verbosity (info) hides debug leaf lines", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  f <- function() {
    log_step("Step")
    log_debug("debug line")
    log_info("info line")
  }
  out <- capture.output(invisible(f()))

  expect_false(any(grepl("debug line", out)))
  expect_true(any(grepl("info line", out)))
})

test_that("verbosity = debug shows debug leaf lines alongside info/success/warn/error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_set_verbosity("debug")

  f <- function() {
    log_step("Step")
    log_debug("debug line")
    log_info("info line")
    log_success("success line")
    log_warn("warn line")
    log_error("error line")
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^\\|- d debug line$", out)))
  expect_true(any(grepl("info line", out)))
  expect_true(any(grepl("success line", out)))
  expect_true(any(grepl("warn line", out)))
  expect_true(any(grepl("error line", out)))
})
