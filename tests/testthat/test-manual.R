test_that("manual open/close at top level yields level-1 siblings", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  out1 <- capture.output({
    s1 <- log_open("Step 1")
    d1 <- find_stack_entry(s1)$depth
    log_close(s1)
  })
  expect_equal(d1, 1L)
  expect_length(the$stack, 0)
  expect_match(out1[1], "^> Step 1$")

  # Second top-level step is a sibling (depth 1), not nested under the first --
  # the whole point of manual close vs. frame-bound log_step() at top level.
  out2 <- capture.output({
    s2 <- log_open("Step 2")
    d2 <- find_stack_entry(s2)$depth
    log_close(s2)
  })
  expect_equal(d2, 1L)
  expect_length(the$stack, 0)
  expect_match(out2[1], "^> Step 2$")
})

test_that("explicit parent nests a step beside the innermost one", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    s1 <- log_open("Parent")
    a  <- log_open("Child A")               # innermost open is s1
    b  <- log_open("Child B", parent = s1)  # linked to s1, not A
  })

  pe <- find_stack_entry(s1)
  ae <- find_stack_entry(a)
  be <- find_stack_entry(b)
  expect_equal(be$parent_id, s1)
  expect_equal(be$depth, pe$depth + 1L)
  expect_equal(be$depth, ae$depth)  # B is a sibling of A
})

test_that("log_close() with no id closes the nearest open step", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    s1 <- log_open("Parent")
    a  <- log_open("Child A")
    log_close()
  })

  expect_null(find_stack_entry(a))
  expect_false(is.null(find_stack_entry(s1)))
  expect_length(the$stack, 1)
})

test_that("linking to an already-closed step errors", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    s1 <- log_open("Parent")
    log_close(s1)
  })

  expect_error(log_open("late", parent = s1), "is not open")
})
