# The `ci` preset: bracketed word glyphs, pure-ASCII connectors, no colour --
# built so captured CI output stays greppable and survives a runner that strips
# ANSI. The words are different lengths on purpose, so the alignment assertion
# below is the one that matters most.

ci_fixture <- function() {
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

test_that("ci resolves by name and is reachable from logtree_theme", {
  withr::defer(logtree_theme("unicode"))

  expect_identical(theme_preset("ci"), glyphs_ci)
  logtree_theme("ci")
  expect_identical(the$theme, console_preset("ci"))

  expect_error(logtree_theme("nope"))
})

test_that("ci carries every slot the built-ins rely on", {
  expect_true(all(names(glyphs_ascii) %in% names(glyphs_ci)))
  for (key in glyph_keys) {
    expect_type(glyphs_ci[[key]]$width, "integer")
  }
})

test_that("ci is colourless in every slot", {
  # A CI runner strips ANSI; emitting it anyway only corrupts the capture.
  for (slot in glyphs_ci) {
    if (is.list(slot)) {
      expect_null(slot$color)
      expect_null(slot$path_color)
      expect_null(slot$slow_color)
    }
  }
})

test_that("ci emits no ANSI even with colour forced on", {
  withr::defer(logtree_theme("unicode"))
  withr::local_options(cli.num_colors = 256)
  logtree_theme("ci")

  line <- format_leaf("error", "boom", 1L)
  expect_false(grepl("\033", line, fixed = TRUE))
  # ... whereas unicode does colour under the same options.
  logtree_theme("unicode")
  expect_true(grepl("\033", format_leaf("error", "boom", 1L), fixed = TRUE))
})

test_that("ci is pure ASCII", {
  keys <- c(glyph_keys, "branch", "corner", "pipe")
  glyphs <- vapply(keys, function(k) glyphs_ci[[k]]$glyph, character(1))
  expect_false(any(grepl("[^\x01-\x7f]", c(glyphs, glyphs_ci$crumb$glyph))))
})

test_that("ci aligns the message column despite differing word widths", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ci")

  # Widest words are "[debug]" / "[break]" at 7; every glyph pads out to that.
  expect_equal(theme_slot_width(), 7L)

  lines <- vapply(
    c("info", "debug", "success", "warning", "error", "interrupted"),
    function(s) format_leaf(s, "msg", 1L, color = FALSE),
    character(1)
  )
  # The message starts at the same column on every one of them.
  expect_equal(length(unique(regexpr("msg", lines, fixed = TRUE))), 1L)
})

test_that("ci spells the corner differently from the branch", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ci")

  entry <- list(depth = 1L, label = "Build", glyph = NULL,
                status = "running", elapsed = 0.5)
  expect_equal(format_open(entry, color = FALSE), "[step]  Build")
  # Close lines drop the word -- "[done] Done" would say it twice.
  expect_equal(format_close(entry, color = FALSE), "\\- [done]  0.50s")
  expect_equal(format_leaf("info", "hello", 1L, color = FALSE),
               "|- [info]  hello")
})

test_that("swapping away from ci restores the built-in close word", {
  withr::defer(logtree_theme("unicode"))

  logtree_theme("ci")
  expect_equal(close_text_template("success"), "")
  logtree_theme("unicode")
  expect_equal(close_text_template("success"), "Done")
})

test_that("ci renders a whole tree", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ci")
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(ci_fixture())
})
