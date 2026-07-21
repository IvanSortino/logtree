render_fixture <- function() {
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
}

test_that("unicode theme renders and aligns as expected", {
  withr::defer(logtree_reset())
  logtree_theme("unicode")
  withr::defer(logtree_theme("unicode"))
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(render_fixture())
})

test_that("ascii theme renders and aligns as expected", {
  withr::defer(logtree_reset())
  local_ascii_theme()
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(render_fixture())
})

test_that("emoji theme renders and aligns as expected", {
  withr::defer(logtree_reset())
  logtree_theme("emoji")
  withr::defer(logtree_theme("unicode"))
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(render_fixture())
})

test_that("message text starts at the same column across themes", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  freeze_clock(c(0, 0, 0.03, 0.15))

  logtree_theme("unicode")
  out_unicode <- capture.output(invisible(render_fixture()))
  logtree_reset()
  freeze_clock(c(0, 0, 0.03, 0.15))

  logtree_theme("ascii")
  out_ascii <- capture.output(invisible(render_fixture()))

  # Top-level step header: glyph + " " + label starts right after the glyph
  # slot in both themes (both presets declare width = 1).
  expect_equal(
    sub("^.", "", out_unicode[1]),
    sub("^.", "", out_ascii[1])
  )
})
