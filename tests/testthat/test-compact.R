# Compact density for logtree_theme(): a smaller per-level tree column, driven
# by theme_col_gap() (the trailing gap) and, for "tight", slimmer connectors.
# ascii is used for the width/render assertions since its output is theme-stable.

compact_fixture <- function() {
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

test_that("resolve_compact maps its argument to NULL / medium / tight", {
  expect_null(resolve_compact(FALSE))
  expect_null(resolve_compact(NULL))
  expect_equal(resolve_compact(TRUE), "tight")
  expect_equal(resolve_compact("medium"), "medium")
  expect_equal(resolve_compact("tight"), "tight")
  expect_error(resolve_compact("huge"))
})

test_that("theme_col_gap defaults to 1L and compact drops it to 0L", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("unicode")
  expect_equal(theme_col_gap(), 1L)

  logtree_theme("unicode", compact = "medium")
  expect_equal(theme_col_gap(), 0L)

  logtree_theme("unicode", compact = "tight")
  expect_equal(theme_col_gap(), 0L)

  # A plain preset swap clears compact (fresh preset carries no col_gap).
  logtree_theme("unicode")
  expect_equal(theme_col_gap(), 1L)
})

test_that("compact shrinks the per-level tree column width", {
  withr::defer(logtree_theme("unicode"))

  # ascii branch connector "|-" is 2 chars; default gap 1 -> 3 columns.
  logtree_theme("ascii")
  expect_equal(tree_col_width(), 3L)

  # medium: gap 0, connectors unchanged -> 2 columns.
  logtree_theme("ascii", compact = "medium")
  expect_equal(tree_col_width(), 2L)
  expect_equal(the$theme$branch$glyph, "|-")

  # tight: gap 0 + connectors slimmed to 1 char -> 1 column.
  logtree_theme("ascii", compact = "tight")
  expect_equal(tree_col_width(), 1L)
  expect_equal(the$theme$branch$glyph, "|")
  expect_equal(the$theme$corner$glyph, "|")
})

test_that("explicit overrides win over the compact profile", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii", compact = "tight",
                overrides = list(branch = list(glyph = "+-")))

  # Override is applied after compact, so branch is the override, not "|".
  expect_equal(the$theme$branch$glyph, "+-")
  # Compact still slimmed the untouched corner and dropped the gap.
  expect_equal(the$theme$corner$glyph, "|")
  expect_equal(theme_col_gap(), 0L)
})

test_that("compact = \"medium\" renders with a tighter tree column (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "medium")
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(compact_fixture())
})

test_that("compact = \"tight\" renders with single-column indentation (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight")
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(compact_fixture())
})
