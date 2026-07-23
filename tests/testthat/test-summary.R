test_that("warnings and errors are auto-recorded; info/success are not", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Task")
    log_info("fyi")
    log_success("ok")
    log_warn("careful")
    log_error("nope")
  }
  capture.output(f())

  statuses <- vapply(the$summary, function(e) e$status, character(1))
  expect_setequal(statuses, c("warning", "error"))
})

test_that("summary = FALSE drops a warning; summary = TRUE pins an info line", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Task")
    log_warn("noisy", summary = FALSE)
    log_info("pinned", summary = TRUE)
  }
  capture.output(f())

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$status, "info")
  expect_identical(the$summary[[1]]$msg, "pinned")
})

test_that("an interrupted step is recorded with no handler installed", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$status, "interrupted")
  expect_identical(the$summary[[1]]$path, c("Outer", "Inner"))
})

test_that("under with_logging(), one failure collapses to a single entry", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  run <- function() with_logging({ outer() }, summary = FALSE)
  capture.output(tryCatch(run(), error = function(e) NULL))

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$kind, "leaf")
  expect_identical(the$summary[[1]]$status, "error")
  expect_match(the$summary[[1]]$msg, "boom")
  expect_identical(the$summary[[1]]$path, c("Outer", "Inner"))
})

test_that("independent sibling failures are both kept", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  one <- function() {
    log_step("One")
    log_error("first")
  }
  two <- function() {
    log_step("Two")
    log_error("second")
  }
  driver <- function() {
    one()
    two()
  }
  capture.output(driver())

  msgs <- vapply(the$summary, function(e) e$msg, character(1))
  expect_setequal(msgs, c("first", "second"))
})

test_that("logtree_summary() prints a header with counts and returns entries invisibly", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w1")
    log_error("e1")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary())
  expect_match(out[[1]], "^Summary: ")
  expect_match(out[[1]], "1 error")
  expect_match(out[[1]], "1 warning")
  expect_length(res, 2L)
  expect_false(withVisible(logtree_summary())$visible)
})

test_that("an empty summary prints nothing-to-report", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_success("done")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary())
  expect_match(out, "nothing to report")
  expect_length(res, 0L)
})

test_that("logtree_reset() clears the summary buffer", {
  logtree_reset()
  withr::defer(logtree_reset())

  f <- function() {
    log_step("T")
    log_warn("w")
  }
  capture.output(f())
  expect_gt(length(the$summary), 0L)

  logtree_reset()
  expect_length(the$summary, 0L)
})

test_that("filter filters the digest to a single status", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w1")
    log_error("e1")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(filter = "error"))
  expect_match(out[[1]], "1 error")
  expect_false(any(grepl("warning", out)))
  expect_length(res, 1L)
  expect_identical(res[[1]]$status, "error")
})

test_that("filter accepts a vector of statuses", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))
  g <- function() {
    log_step("T2")
    log_warn("careful")
  }
  capture.output(g())

  res <- logtree_summary(filter = c("warning", "interrupted"))
  statuses <- vapply(res, function(e) e$status, character(1))
  expect_setequal(statuses, c("interrupted", "warning"))
})

test_that("filter with no matching status reports nothing", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(filter = "error"))
  expect_match(out, "nothing to report")
  expect_length(res, 0L)
})

test_that("logtree_summary() prints outcome words for non-leaf step entries", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # A step that elevates via a summary = FALSE leaf records a *step* entry (the
  # leaf itself is dropped), so logtree_summary() renders the switch()-mapped
  # outcome word rather than a message.
  warned <- function() {
    log_step("Warned")
    log_warn("quiet", summary = FALSE)
  }
  failed <- function() {
    log_step("Failed")
    log_error("quiet", summary = FALSE)
  }
  capture.output({ warned(); failed() })

  out <- capture.output(logtree_summary())
  expect_true(any(grepl("Warned  completed with warning", out)))
  expect_true(any(grepl("Failed  failed", out)))
})

test_that("logtree_summary() reports an interrupted step as 'did not complete'", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))

  out <- capture.output(logtree_summary())
  expect_true(any(grepl("did not complete", out)))
})
