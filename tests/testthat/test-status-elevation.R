test_that("log_warn elevates the enclosing step's close glyph", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Fetching")
    log_warn("Retry 1/3 due to timeout")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- ! Done")
})

test_that("log_error elevates the enclosing step's close glyph", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Classifying")
    log_error("model timeout after 30s")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- x Done")
})

test_that("severity never downgrades: error after warning stays error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Step")
    log_warn("first a warning")
    log_error("then an error")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- x Done")
})

test_that("severity never downgrades: warning after error stays error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Step")
    log_error("an error first")
    log_warn("then a warning")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- x Done")
})

test_that("log_info/log_success do not elevate status", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Step")
    log_info("just informational")
    log_success("looks fine")
  }

  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- \\+ Done")
})
