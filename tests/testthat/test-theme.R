test_that("logtree_theme(preset) fully swaps the glyph set", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii")
  expect_equal(the$theme$success$glyph, "+")

  logtree_theme("unicode")
  expect_false(identical(the$theme$success$glyph, "+"))
})

test_that("logtree_theme(list(...)) merges overrides onto the active theme", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii")
  logtree_theme(list(success = list(glyph = "*")))

  expect_equal(the$theme$success$glyph, "*")
  # Unspecified fields (width, color) are preserved from the existing entry.
  expect_equal(the$theme$success$width, 1L)
  # Other keys are untouched by a partial override.
  expect_equal(the$theme$error$glyph, "x")
})

test_that("logtree_theme(theme=, overrides=) applies overrides after a preset swap", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("unicode", overrides = list(warning = list(glyph = "W")))

  expect_equal(the$theme$warning$glyph, "W")
  expect_equal(the$theme$success$glyph, glyphs_unicode$success$glyph)
})

test_that("a call naming no preset merges onto the active theme", {
  withr::defer(logtree_theme("unicode"))

  # The trap this replaced: `overrides =` used to re-resolve `theme` to its
  # default and swap the whole preset back to unicode.
  logtree_theme("ascii")
  logtree_theme(overrides = list(crumb = list(glyph = " / ")))
  expect_equal(the$theme$step$glyph, ">")
  expect_equal(the$theme$crumb$glyph, " / ")

  # Same for a compact-only call.
  logtree_theme(compact = "tight")
  expect_equal(the$theme$step$glyph, ">")
  expect_equal(the$theme$col_gap, 0L)

  # And a bare call changes nothing at all.
  logtree_theme()
  expect_equal(the$theme$step$glyph, ">")
  expect_equal(the$theme$crumb$glyph, " / ")
})

test_that("naming a preset swaps it, clearing earlier overrides", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii")
  logtree_theme(list(crumb = list(glyph = " / ")))
  logtree_theme("ascii")
  expect_equal(the$theme$crumb$glyph, glyphs_ascii$crumb$glyph)
})

test_that("an unknown override slot errors, naming it and the valid slots", {
  withr::defer(logtree_theme("unicode"))

  expect_error(
    logtree_theme(list(crumbs = list(glyph = " / "))),
    "Unknown theme slot: `crumbs`",
    fixed = TRUE
  )
  expect_error(logtree_theme(list(crumbs = list())), "Valid slots: ")
  expect_error(
    logtree_theme(list(nope = list(), alsono = list())),
    "Unknown theme slots: `nope`, `alsono`",
    fixed = TRUE
  )
  # col_gap is a theme internal (set through `compact`), not an override slot,
  # even once compact has put it on the theme.
  logtree_theme("unicode", compact = "medium")
  expect_equal(the$theme$col_gap, 0L)
  expect_error(logtree_theme(list(col_gap = 1L)), "Unknown theme slot")
  # A slot the user forgot to name at all.
  expect_error(logtree_theme(list(list(glyph = "*"))), "must be a named list")

  # The active theme is left untouched by a rejected call.
  logtree_theme("ascii")
  try(logtree_theme(list(crumbs = list(glyph = "!"))), silent = TRUE)
  expect_equal(the$theme$step$glyph, ">")
})

test_that("logtree_theme rejects an invalid theme argument", {
  withr::defer(logtree_theme("unicode"))
  expect_error(logtree_theme(42))
})

test_that("logtree_theme rejects an unknown preset name", {
  withr::defer(logtree_theme("unicode"))
  expect_error(logtree_theme("nonexistent"))
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
  withr::defer(logtree_theme("unicode"))

  # Default: folder glyph, magenta, no brackets (bracket defaults FALSE).
  logtree_theme("unicode")
  entry  <- list(depth = 1L, name = "Item 1")
  folder <- glyphs_unicode$group$glyph
  expect_equal(format_group_header(entry, color = FALSE), paste0(folder, " Item 1"))

  # bracket = TRUE opts the < > wrapper back in, glyph still prepended.
  logtree_theme(overrides = list(group = list(bracket = TRUE)))
  expect_equal(format_group_header(entry, color = FALSE), paste0(folder, " < Item 1 >"))

  # A glyph + color + bracket override merges like any other theme key. Note an
  # overrides-only call re-resolves to the unicode preset first, so bracket must
  # be restated here to survive the reset (see logtree_theme semantics).
  logtree_theme(overrides = list(group = list(glyph = "#", color = "magenta", bracket = TRUE)))
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
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ascii")
  expect_equal(the$theme$debug$glyph, "d")

  logtree_theme("unicode")
  expect_equal(the$theme$debug$glyph, "⚙")

  logtree_theme("emoji")
  expect_equal(the$theme$debug$glyph, "\U0001f41b")
})

test_that("the done slot styles the close line without touching success leaves", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # List form: merge onto the active (ascii) theme rather than re-resolving
  # to the unicode preset, as `overrides =` with no `theme` would.
  logtree_theme(list(done = list(glyph = "=")))

  f <- function() {
    log_step("Work")
    log_success("all good")
  }
  out <- capture.output(invisible(f()))

  # The log_success() leaf keeps the ascii success glyph ...
  expect_match(out[2], "^\\|- \\+ all good$")
  # ... while the step's own Done line now uses the done glyph.
  expect_match(out[3], "^\\|- = Done")
  # The success slot itself is untouched by a done override.
  expect_equal(the$theme$success$glyph, "+")
})

test_that("a success override leaves the Done line's glyph alone", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  logtree_theme(list(success = list(glyph = "*")))

  f <- function() {
    log_step("Work")
    log_success("all good")
  }
  out <- capture.output(invisible(f()))

  expect_match(out[2], "^\\|- \\* all good$")
  expect_match(out[3], "^\\|- \\+ Done")
})

test_that("done only governs a clean close: elevated statuses keep their slot", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  logtree_theme(list(done = list(glyph = "=")))

  f <- function() {
    log_step("Work")
    log_warn("something odd")
  }
  out <- capture.output(invisible(f()))

  expect_match(out[3], "^\\|- ! Done")
})

test_that("every preset ships a done slot matching its success glyph", {
  withr::defer(logtree_theme("unicode"))

  for (preset in list(glyphs_unicode, glyphs_ascii, glyphs_emoji)) {
    expect_equal(preset$done$glyph, preset$success$glyph)
    expect_equal(preset$done$width, preset$success$width)
  }
})

test_that("a theme with no done slot falls back to the success glyph", {
  # Themes built before the `done` slot existed (or hand-assembled ones) must
  # keep rendering their close lines with `success`.
  legacy <- glyphs_ascii
  legacy$done <- NULL
  entry <- list(depth = 1L, status = "running", elapsed = 0)

  expect_equal(close_glyph_key("success", legacy), "success")
  expect_match(format_close(entry, theme = legacy, color = FALSE), "^\\|- \\+ Done")
  # And the missing slot does not break column alignment for the others.
  expect_equal(theme_slot_width(legacy), 1L)
})

test_that("theme_preset() errors on an unknown preset name", {
  # logtree_theme() guards preset names via match.arg() before this internal is
  # reached, so exercise theme_preset()'s own fallback stop() directly.
  expect_error(theme_preset("nonexistent"), "Unknown theme preset")
})
