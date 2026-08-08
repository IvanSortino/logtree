# The `minimal` preset: no connector glyphs at all, so depth is carried by
# indentation alone (col_gap 2). The layout math is unchanged -- what is tested
# here is that empty connectors feed through it correctly, and that the
# preset's deliberate trades stay deliberate.

minimal_fixture <- function() {
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

test_that("minimal resolves by name and is reachable from logtree_theme", {
  withr::defer(logtree_theme("unicode"))

  expect_identical(theme_preset("minimal"), glyphs_minimal)
  logtree_theme("minimal")
  expect_identical(the$theme, console_preset("minimal"))
})

test_that("minimal carries every slot the built-ins rely on", {
  # A preset missing a slot renders a broken tree; pin the contract rather than
  # discovering it through a snapshot diff later.
  expect_true(all(names(glyphs_ascii) %in% names(glyphs_minimal)))
  # Each status slot declares its own width -- alignment cannot be measured.
  for (key in glyph_keys) {
    expect_type(glyphs_minimal[[key]]$width, "integer")
  }
})

test_that("minimal indents by col_gap alone, with no connector glyphs", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("minimal")

  expect_equal(the$theme$branch$glyph, "")
  expect_equal(the$theme$corner$glyph, "")
  expect_equal(the$theme$pipe$glyph, "")

  # 0-width connectors + col_gap 2 -> two columns per level, and the rail unit
  # pads the empty pipe out to that same width so nesting still lines up.
  expect_equal(theme_col_gap(), 2L)
  expect_equal(tree_col_width(), 2L)
  expect_equal(rail_unit(color = FALSE), "  ")
})

test_that("minimal renders depth as pure indentation", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("minimal")

  entry <- function(d) list(depth = d, label = "step", glyph = NULL,
                            status = "running", elapsed = 0.5)
  expect_equal(format_open(entry(1L), color = FALSE), "▸ step")
  expect_equal(format_open(entry(2L), color = FALSE), "  ▸ step")
  expect_equal(format_open(entry(3L), color = FALSE), "    ▸ step")

  # Close lines drop the word: the preset ships done$text = "".
  expect_equal(format_close(entry(1L), color = FALSE), "  ✓ 0.50s")
})

test_that("minimal tells info, debug and interrupted apart by colour alone", {
  # This is the trade the preset makes -- assert it deliberately, so changing
  # any of the three glyphs later is a decision rather than an accident.
  expect_equal(glyphs_minimal$info$glyph, glyphs_minimal$debug$glyph)
  expect_equal(glyphs_minimal$info$glyph, glyphs_minimal$interrupted$glyph)
  expect_false(identical(glyphs_minimal$info$color, glyphs_minimal$debug$color))
  expect_false(identical(glyphs_minimal$info$color,
                         glyphs_minimal$interrupted$color))
})

test_that("compact tightens minimal without flattening it", {
  withr::defer(logtree_theme("unicode"))

  # minimal has no connector glyphs, so col_gap *is* its whole indentation.
  # Zeroing it the way compact does for other presets would render every depth
  # at the left margin, turning the tree into a flat list.
  # A list, not c(): c("medium", "tight", TRUE) would coerce TRUE to "TRUE".
  for (level in list("medium", "tight", TRUE)) {
    logtree_theme("minimal", compact = level)
    expect_equal(tree_col_width(), 1L)

    entry <- function(d) list(depth = d, label = "step", glyph = NULL,
                              status = "running", elapsed = 0.5)
    rendered <- vapply(1:3, function(d) format_open(entry(d), color = FALSE),
                       character(1))
    # Each level is still indented one column further than the last.
    expect_equal(rendered, c("▸ step", " ▸ step", "  ▸ step"))
  }
})

test_that("swapping away from minimal clears its col_gap", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("minimal")
  expect_equal(theme_col_gap(), 2L)
  logtree_theme("unicode")
  expect_equal(theme_col_gap(), 1L)
})

test_that("minimal renders a whole tree", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("minimal")
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(minimal_fixture())
})
