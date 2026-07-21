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

test_that("logtree_set_verbosity rejects an invalid level", {
  local_reset_verbosity()
  expect_error(logtree_set_verbosity("nonexistent"))
})
