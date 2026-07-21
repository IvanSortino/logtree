test_that("logtree_reset clears the stack and id counter but not theme/sinks", {
  logtree_reset()
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  local_reset_sinks()

  logtree_theme("ascii")
  path <- tempfile()
  logtree_sink_file(path, format = "text")

  # Called directly (not via a one-line wrapper function) so the step stays
  # open in this test_that block's own frame until we've made our
  # assertions -- a one-line `function() log_step(...)` would close the
  # step the instant it returns, before we could inspect the stack.
  log_step("Step")
  expect_length(the$stack, 1)

  logtree_reset()
  expect_length(the$stack, 0)
  expect_equal(the$theme$success$glyph, "+")   # theme untouched by reset
  expect_length(the$sinks, 2)                   # sinks untouched by reset
})

test_that("close_step is a no-op for an id that isn't on the stack", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_no_error(close_step(999999L))
  expect_length(the$stack, 0)
})

test_that("find_stack_entry returns NULL for an unknown id", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_null(find_stack_entry(999999L))
})

test_that("elevate_current_step is a no-op when no step is open", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_no_error(elevate_current_step("error"))
  expect_length(the$stack, 0)
})

test_that("step ids are unique and monotonically increasing across pushes", {
  logtree_reset()
  withr::defer(logtree_reset())

  f <- function() {
    id1 <- log_step("A")
    id2 <- log_step("B")
    c(id1, id2)
  }
  ids <- f()
  expect_true(ids[2] > ids[1])
})
