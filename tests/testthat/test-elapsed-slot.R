# The `elapsed` theme slot: how a close line's time column is gated (`show`,
# `min`) and styled (`color`, `slow`, `slow_color`), via format_elapsed_field().
# ascii is used for the render assertions since its output is theme-stable.

elapsed_entry <- function(seconds) {
  list(depth = 1L, label = "Build", status = "running", elapsed = seconds)
}

test_that("the built-in slot leaves every time visible and unstyled", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii")

  expect_equal(format_elapsed_field(0, color = FALSE), "0.00s")
  expect_equal(format_elapsed_field(0.5, color = FALSE), "0.50s")
  expect_equal(format_elapsed_field(90, color = FALSE), "1m 30s")
})

test_that("show = FALSE drops the time column entirely", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(elapsed = list(show = FALSE)))

  expect_equal(format_elapsed_field(2.5, color = FALSE), "")
  # The word survives on its own, with no dangling separator after it.
  expect_equal(format_close(elapsed_entry(2.5), color = FALSE), "|- + Done")
})

test_that("min hides times below the threshold and keeps the rest", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(elapsed = list(min = 0.1)))

  expect_equal(format_elapsed_field(0.004, color = FALSE), "")
  expect_equal(format_elapsed_field(0.099, color = FALSE), "")
  # The threshold is inclusive: exactly `min` is slow enough to show.
  expect_equal(format_elapsed_field(0.1, color = FALSE), "0.10s")
  expect_equal(format_elapsed_field(2.5, color = FALSE), "2.50s")

  expect_equal(format_close(elapsed_entry(0.004), color = FALSE), "|- + Done")
  expect_equal(format_close(elapsed_entry(2.5), color = FALSE), "|- + Done  2.50s")
})

test_that("slow / slow_color restyle only the times at or over the threshold", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", overrides = list(
    elapsed = list(color = "silver", slow = 1, slow_color = "red")
  ))
  withr::local_options(cli.num_colors = 256)

  # Below the threshold: the base `color`.
  expect_match(format_elapsed_field(0.3), "\033\\[90m0\\.30s")
  # At and above it: `slow_color` replaces the base colour.
  expect_match(format_elapsed_field(1), "\033\\[31m1\\.00s")
  expect_match(format_elapsed_field(4.2), "\033\\[31m4\\.20s")

  # color = FALSE strips styling entirely, as it does everywhere else.
  expect_equal(format_elapsed_field(4.2, color = FALSE), "4.20s")
})

test_that("a theme with no elapsed slot renders exactly as before", {
  # Hand-assembled themes, and any built before the slot existed, must keep
  # working -- theme_field() degrades every missing field to its default.
  legacy <- glyphs_ascii
  legacy$elapsed <- NULL

  expect_equal(format_elapsed_field(2.5, theme = legacy, color = FALSE), "2.50s")
  expect_equal(
    format_close(elapsed_entry(2.5), theme = legacy, color = FALSE),
    "|- + Done  2.50s"
  )
})

test_that("gate = FALSE keeps the styling but skips the hiding rules", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(elapsed = list(show = FALSE, min = 10)))

  # This is what print_run_summary() relies on: "Run complete in <time>" would
  # read as an unfinished sentence if the time could be suppressed.
  expect_equal(format_elapsed_field(0.004, gate = FALSE, color = FALSE), "0.00s")
  expect_equal(format_elapsed_field(2.5, gate = FALSE, color = FALSE), "2.50s")
  # ... while the gated path still hides them.
  expect_equal(format_elapsed_field(2.5, color = FALSE), "")
})

test_that("the run-summary line always prints its own time", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(elapsed = list(show = FALSE)))
  freeze_clock(c(0, 0.25))

  expect_output(print_run_summary("success", 0.25), "Run complete in 0\\.25s")
})

test_that("dropping both the word and the time leaves a glyph-only close", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(
    elapsed = list(show = FALSE),
    done    = list(text = "")
  ))

  # No trailing gap is left hanging off the end of the line.
  expect_equal(format_close(elapsed_entry(2.5), color = FALSE), "|- +")
})

test_that("file sinks keep every time whatever the console theme hides", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", overrides = list(elapsed = list(show = FALSE)))

  # File sinks render through the ascii preset, which carries its own slot.
  expect_equal(
    format_close(elapsed_entry(2.5), theme = glyphs_ascii, color = FALSE),
    "|- + Done  2.50s"
  )
})

test_that("min = 0.1 silences the fast steps of a whole tree (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(elapsed = list(min = 0.1)))
  # Inner step takes 0.03s (hidden), outer 0.15s (shown).
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot({
    logtree_reset()
    pipeline <- function() {
      log_step("Pipeline")
      load_config()
    }
    load_config <- function() {
      log_step("Load config")
      log_info("Reading config.yml")
    }
    pipeline()
  })
})
