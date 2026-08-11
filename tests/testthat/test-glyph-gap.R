# Glyph gap: the spacing between a line's status glyph and its message text,
# driven by theme_glyph_gap() / glyph_pad(). ascii is used for the render
# assertions since its output is theme-stable and easy to pattern-match.

gap_fixture <- function() {
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

test_that("resolve_glyph_gap accepts non-negative scalars and rejects the rest", {
  expect_null(resolve_glyph_gap(NULL))
  expect_identical(resolve_glyph_gap(0), 0L)
  expect_identical(resolve_glyph_gap(2), 2L)
  expect_identical(resolve_glyph_gap(3L), 3L)

  expect_error(resolve_glyph_gap(-1), "non-negative")
  expect_error(resolve_glyph_gap(c(1, 2)), "non-negative")
  expect_error(resolve_glyph_gap("1"), "non-negative")
  expect_error(resolve_glyph_gap(NA), "non-negative")
})

test_that("theme_glyph_gap defaults to 1L and follows logtree_theme(glyph_gap=)", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("unicode")
  expect_equal(theme_glyph_gap(), 1L)

  logtree_theme(glyph_gap = 0)
  expect_equal(theme_glyph_gap(), 0L)

  logtree_theme(glyph_gap = 3)
  expect_equal(theme_glyph_gap(), 3L)

  # A preset swap clears it (a fresh preset carries no glyph_gap), as it does
  # for compact.
  logtree_theme("unicode")
  expect_equal(theme_glyph_gap(), 1L)
})

test_that("glyph_gap = NULL leaves the active setting alone", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii", glyph_gap = 2)
  logtree_theme(overrides = list(info = list(glyph = "*")))
  expect_equal(theme_glyph_gap(), 2L)
})

test_that("glyph_gap widens every line kind's message column", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", glyph_gap = 2,
                overrides = list(group = list(glyph = "#")))

  entry <- list(depth = 1L, label = "Build", glyph = NULL,
                status = "running", elapsed = 0.5)
  expect_equal(format_open(entry, color = FALSE), ">  Build")
  expect_equal(format_close(entry, color = FALSE), "|- +  Done  0.50s")
  expect_equal(format_leaf("info", "hello", 1L, color = FALSE), "|- i  hello")
  # The group header's marker takes the same gap before the header name.
  expect_equal(
    format_group_header(list(depth = 1L, name = "Suite 1"), color = FALSE),
    "#  < Suite 1 >"
  )
})

test_that("glyph_gap = 0 butts the message against the glyph", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", glyph_gap = 0)

  entry <- list(depth = 1L, label = "Build", glyph = NULL,
                status = "running", elapsed = 0.5)
  expect_equal(format_open(entry, color = FALSE), ">Build")
  expect_equal(format_close(entry, color = FALSE), "|- +Done  0.50s")
  expect_equal(format_leaf("info", "hello", 1L, color = FALSE), "|- ihello")
})

test_that("file sinks keep the built-in spacing whatever the console gap is", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", glyph_gap = 4)

  # File sinks render through the ascii preset, which carries no glyph_gap --
  # console spacing is a console concern (design doc section 6).
  entry <- list(depth = 1L, label = "Build", glyph = NULL, status = "running")
  expect_equal(
    format_open(entry, theme = glyphs_ascii, color = FALSE),
    "> Build"
  )
})

test_that("glyph_gap = 2 renders a roomier tree (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", glyph_gap = 2)
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(gap_fixture())
})

test_that("glyph_gap composes with compact = \"tight\" (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight", glyph_gap = 0)
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(gap_fixture())
})
