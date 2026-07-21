test_that("logtree_set_theme(preset) fully swaps the glyph set", {
  withr::defer(logtree_set_theme("unicode"))

  logtree_set_theme("ascii")
  expect_equal(the$theme$success$glyph, "+")

  logtree_set_theme("unicode")
  expect_false(identical(the$theme$success$glyph, "+"))
})

test_that("logtree_set_theme(list(...)) merges overrides onto the active theme", {
  withr::defer(logtree_set_theme("unicode"))

  logtree_set_theme("ascii")
  logtree_set_theme(list(success = list(glyph = "*")))

  expect_equal(the$theme$success$glyph, "*")
  # Unspecified fields (width, color) are preserved from the existing entry.
  expect_equal(the$theme$success$width, 1L)
  # Other keys are untouched by a partial override.
  expect_equal(the$theme$error$glyph, "x")
})

test_that("logtree_set_theme(theme=, overrides=) applies overrides after a preset swap", {
  withr::defer(logtree_set_theme("unicode"))

  logtree_set_theme("unicode", overrides = list(warning = list(glyph = "W")))

  expect_equal(the$theme$warning$glyph, "W")
  expect_equal(the$theme$success$glyph, glyphs_unicode$success$glyph)
})

test_that("logtree_set_theme rejects an invalid theme argument", {
  withr::defer(logtree_set_theme("unicode"))
  expect_error(logtree_set_theme(42))
})

test_that("logtree_set_theme rejects an unknown preset name", {
  withr::defer(logtree_set_theme("unicode"))
  expect_error(logtree_set_theme("nonexistent"))
})

test_that("a per-call glyph override in log_step() replaces only that step's glyph", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Custom", glyph = "@")
  }
  out <- capture.output(invisible(f()))
  expect_match(out[1], "^@ Custom$")
})

test_that("logtree_threshold rejects an invalid level", {
  local_reset_verbosity()
  expect_error(logtree_threshold("nonexistent"))
})

test_that("group theme slot styles the header glyph, color, and brackets", {
  withr::defer(logtree_set_theme("unicode"))

  # Default: folder glyph, magenta, no brackets (bracket defaults FALSE).
  logtree_set_theme("unicode")
  entry  <- list(depth = 1L, name = "Item 1")
  folder <- glyphs_unicode$group$glyph
  expect_equal(format_group_header(entry, color = FALSE), paste0(folder, " Item 1"))

  # bracket = TRUE opts the < > wrapper back in, glyph still prepended.
  logtree_set_theme(overrides = list(group = list(bracket = TRUE)))
  expect_equal(format_group_header(entry, color = FALSE), paste0(folder, " < Item 1 >"))

  # A glyph + color + bracket override merges like any other theme key. Note an
  # overrides-only call re-resolves to the unicode preset first, so bracket must
  # be restated here to survive the reset (see logtree_set_theme semantics).
  logtree_set_theme(overrides = list(group = list(glyph = "#", color = "magenta", bracket = TRUE)))
  expect_equal(the$theme$group$glyph, "#")

  # No-color path prepends the glyph and keeps the brackets, no ANSI.
  expect_equal(format_group_header(entry, color = FALSE), "# < Item 1 >")

  # Color path wraps the header in ANSI while leaving the text intact.
  withr::local_options(cli.num_colors = 256L)
  colored <- format_group_header(entry, color = TRUE)
  expect_match(colored, "\\[")
  expect_match(colored, "# < Item 1 >")
})

test_that("each theme preset defines a distinct debug glyph", {
  withr::defer(logtree_set_theme("unicode"))

  logtree_set_theme("ascii")
  expect_equal(the$theme$debug$glyph, "d")

  logtree_set_theme("unicode")
  expect_equal(the$theme$debug$glyph, "⚙")

  logtree_set_theme("emoji")
  expect_equal(the$theme$debug$glyph, "\U0001f41b")
})
