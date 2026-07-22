test_that("leaf close = TRUE renders a corner leaf and no Done line (unicode)", {
  logtree_reset()
  withr::defer(logtree_reset())
  logtree_theme("unicode")
  withr::defer(logtree_theme("unicode"))

  expect_snapshot({
    log_open("Step 2")
    log_warn("child warn 1", close = TRUE)
  })
})

test_that("leaf close = TRUE emits no Done line and ends on the corner leaf", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  out <- capture.output({
    log_open("Step 2")
    log_warn("child warn 1", close = TRUE)
  })

  expect_false(any(grepl("Done", out)))
  expect_match(out[length(out)], "! child warn 1$")
})

test_that("leaf close = TRUE pops the enclosing step off the stack", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    log_open("Outer")
    log_open("Inner")
    expect_length(the$stack, 2)
    log_info("closing inner", close = TRUE)
  })

  # Inner is gone; Outer stays open at its original depth.
  expect_length(the$stack, 1)
  expect_equal(the$stack[[1]]$label, "Outer")
  expect_equal(the$stack[[1]]$depth, 1L)
})

test_that("after a force-close the next sibling opens at the outer depth", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    log_open("Outer")             # depth 1
    log_open("Inner")             # depth 2
    log_info("bye", close = TRUE) # closes Inner
    sib <- log_open("Sibling")    # innermost is Outer again -> depth 2
  })

  expect_equal(find_stack_entry(sib)$depth, 2L)
  expect_equal(find_stack_entry(sib)$parent_id, the$stack[[1]]$id)
})

test_that("log_open(close = TRUE) prints a header-only marker and leaves no open step", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  out <- capture.output(log_open("Marker only", close = TRUE))

  expect_equal(out, "> Marker only")
  expect_length(the$stack, 0)
})

test_that("log_step(close = TRUE) is a header-only marker with no auto-close registered", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    out <- capture.output(log_step("checkpoint", close = TRUE))
    expect_equal(out, "> checkpoint")
    expect_length(the$stack, 0)
  }
  f()

  # The frame has exited; the skipped defer must not touch the (empty) stack.
  expect_length(the$stack, 0)
})

test_that("silent close still folds a member's warning into its group's close line", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  freeze_clock(0)

  out <- capture.output({
    g <- function() {
      log_step("record 1", group_by = c(Batch = "nightly"))
      log_warn("checksum mismatch", close = TRUE)  # closes record 1 silently
      log_step("record 2", group_by = c(Batch = "nightly"))
    }
    g()
    log_open("done batching")  # ungrouped sibling settles the group
  })

  # record 1 emitted no Done line of its own ...
  expect_false(any(grepl("mismatch.*Done", out)))
  # ... yet the group closes with the warning glyph folded up from it.
  expect_true(any(grepl("^\\|- ! Done", out)))
})
