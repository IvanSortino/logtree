test_that("log_step() at top level warns that it can't auto-close", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # The one-time nudge fires only when the caller frame is the global env, and
  # only once per session -- reset its frequency so this assertion is reliable
  # regardless of whether an earlier test/demo already tripped it.
  rlang::reset_message_verbosity("logtree_log_step_toplevel")

  expect_message(
    capture.output(evalq(log_step("top-level step"), globalenv())),
    "won't auto-close"
  )
})
