test_that("nesting via function calls unwinds depth to zero", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    invisible(NULL)
  }
  outer <- function() {
    log_step("Outer")
    inner()
    invisible(NULL)
  }

  outer()
  expect_length(the$stack, 0)
})

test_that("Tier-1-only: uncaught error still unwinds depth with no with_logging()", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("risky")
    stop("boom")
  }

  tryCatch(f(), error = function(e) NULL)
  expect_length(the$stack, 0)
})

test_that("Tier-1-only: interrupted step renders as interrupted, not success", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("risky")
    stop("boom")
  }

  out <- capture.output(invisible(tryCatch(f(), error = function(e) NULL)))
  close_line <- out[length(out)]
  expect_match(close_line, "^\\|- - Done")
})

test_that("same-frame siblings nest B under A and unwind cleanly", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  foo <- function() {
    log_step("A")
    log_step("B")
  }

  out <- capture.output(invisible(foo()))
  expect_length(the$stack, 0)
  # B opens while A is still open, so B renders nested under A.
  expect_match(out[1], "^> A$")
  expect_match(out[2], "^\\|- > B$")
  # B (pushed second) must close before A -- LIFO order. Neither step logged
  # a warning/error, so both close as success. The rail column is as wide
  # as the connector ("|- " = 3 chars), so B's close line pads with two
  # spaces after the pipe, not one.
  expect_match(out[3], "^\\|  \\|- \\+ Done")
  expect_match(out[4], "^\\|- \\+ Done")
})
