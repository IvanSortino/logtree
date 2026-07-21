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
    da <- find_stack_entry(a)$depth
    b  <- log_open("Child B", parent = s1)  # linked to s1, not A
  })

  pe <- find_stack_entry(s1)
  be <- find_stack_entry(b)
  expect_equal(be$parent_id, s1)
  expect_equal(be$depth, pe$depth + 1L)
  expect_equal(be$depth, da)          # B is a sibling of A (same depth)
})

test_that("opening a sibling via parent= auto-closes the prior sibling", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  capture.output({
    s1 <- log_open("Parent")
    a  <- log_open("Child A")
    gc <- log_open("Grandchild")            # open descendant of A
    b  <- log_open("Child B", parent = s1)  # A's subtree is now a finished sibling
  })

  expect_null(find_stack_entry(a))          # A auto-closed
  expect_null(find_stack_entry(gc))         # and its open descendant, cascaded
  expect_false(is.null(find_stack_entry(b)))
  # Stack is Parent -> B; the whole A subtree was retired.
  expect_length(the$stack, 2)
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
