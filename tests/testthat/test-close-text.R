# Themeable close-line text: the word a step's close line prints before its
# elapsed time, resolved by close_text_template() through the status slot, then
# the `done` slot, then the built-in "Done". ascii is used for the render
# assertions since its output is theme-stable and easy to pattern-match.

close_entry <- function(status = "running", ...) {
  utils::modifyList(
    list(depth = 1L, label = "Build", status = status, elapsed = 0.5),
    list(...)
  )
}

test_that("close_text_template falls back status -> done -> \"Done\"", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii")

  # Every preset ships "Done" on the `done` slot.
  expect_equal(close_text_template("success"), "Done")
  # A clean close reads `done`, not `success` -- close_glyph_key()'s rule.
  expect_equal(close_glyph_key("success", the$theme), "done")

  # `done` renames every close line, whatever the status.
  logtree_theme(list(done = list(text = "Complete")))
  expect_equal(close_text_template("success"), "Complete")
  expect_equal(close_text_template("error"), "Complete")

  # A per-status `text` wins for that status only.
  logtree_theme(list(error = list(text = "Failed")))
  expect_equal(close_text_template("error"), "Failed")
  expect_equal(close_text_template("warning"), "Complete")
  expect_equal(close_text_template("success"), "Complete")
})

test_that("a theme carrying no text anywhere still renders \"Done\"", {
  # Hand-assembled themes, and any built before `text` existed, must keep
  # working -- theme_field() degrades a missing field to its default.
  legacy <- glyphs_ascii
  legacy$done$text <- NULL
  expect_equal(close_text_template("success", legacy), "Done")

  legacy$done <- NULL
  expect_equal(close_text_template("success", legacy), "Done")
})

test_that("expand_close_text substitutes {label} and {elapsed}", {
  entry <- close_entry()
  expect_equal(expand_close_text("{label}", entry, "0.50s"), "Build")
  expect_equal(expand_close_text("{label} in {elapsed}", entry, "0.50s"),
               "Build in 0.50s")
  # No placeholders: the template passes through untouched.
  expect_equal(expand_close_text("Done", entry, "0.50s"), "Done")

  # A group close carries `name` rather than `label`.
  group <- list(depth = 1L, name = "Suite 1", status = "running", elapsed = 0.5)
  expect_equal(expand_close_text("{label}", group, "0.50s"), "Suite 1")

  # Neither field present -> empty, not an error (gsub rejects NULL).
  bare <- list(depth = 1L, status = "running", elapsed = 0.5)
  expect_equal(expand_close_text("[{label}]", bare, "0.50s"), "[]")
})

test_that("a substituted value is data, never rescanned as a template", {
  # Placeholders are expanded in ONE pass. Two sequential gsub()s would let a
  # step labelled "{elapsed}" have its own label reinterpreted, printing the
  # time where the label belongs -- log data must not steer the template.
  entry <- close_entry(label = "{elapsed}")
  expect_equal(expand_close_text("{label}", entry, "0.50s"), "{elapsed}")
  expect_equal(expand_close_text("[{label}]", entry, "0.50s"), "[{elapsed}]")

  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(done = list(text = "{label}")))
  # ... and the time is still appended once, not twice.
  expect_equal(close_message(entry, "success"), "{elapsed}  0.50s")
})

test_that("a label with regex or backreference syntax survives intact", {
  entry <- close_entry(label = "a\\1b $x [0-9]+")
  expect_equal(expand_close_text("{label}", entry, "0.50s"), "a\\1b $x [0-9]+")
})

test_that("close_message joins the word and the time only when both are there", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii")
  entry <- close_entry()

  expect_equal(close_message(entry, "success"), "Done  0.50s")

  # text = "" drops the word; no dangling separator is left behind.
  logtree_theme(list(done = list(text = "")))
  expect_equal(close_message(entry, "success"), "0.50s")
})

test_that("a template placing {elapsed} itself owns the time column", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii")
  entry <- close_entry()

  # Without this the time would render twice -- once inside the template, once
  # appended after it.
  logtree_theme(list(done = list(text = "took {elapsed}")))
  expect_equal(close_message(entry, "success"), "took 0.50s")

  logtree_theme(list(done = list(text = "{label} took {elapsed}")))
  expect_equal(close_message(entry, "success"), "Build took 0.50s")
})

test_that("format_close renders the themed word", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii")
  entry <- close_entry()

  expect_equal(format_close(entry, color = FALSE), "|- + Done  0.50s")

  logtree_theme(list(done = list(text = "Complete")))
  expect_equal(format_close(entry, color = FALSE), "|- + Complete  0.50s")

  logtree_theme(list(error = list(text = "Failed")))
  expect_equal(format_close(close_entry("error"), color = FALSE),
               "|- x Failed  0.50s")
  # The success path is untouched by an `error` override.
  expect_equal(format_close(entry, color = FALSE), "|- + Complete  0.50s")
})

test_that("close text is a close-line concern only, not leaf text", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(error = list(text = "Failed")))

  # log_error()'s own message is untouched: `text` governs close lines.
  expect_equal(format_leaf("error", "model timeout", 1L, color = FALSE),
               "|- x model timeout")
})

test_that("file sinks keep \"Done\" whatever the console theme says", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", overrides = list(done = list(text = "Complete")))

  # File sinks render through the ascii preset, which carries its own text.
  expect_equal(
    format_close(close_entry(), theme = glyphs_ascii, color = FALSE),
    "|- + Done  0.50s"
  )
})

test_that("a renamed close line renders through a whole tree (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", overrides = list(
    done  = list(text = "{label} ok"),
    error = list(text = "{label} FAILED")
  ))
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot({
    logtree_reset()
    pipeline <- function() {
      log_step("Pipeline")
      load_config()
    }
    load_config <- function() {
      log_step("Load config")
      log_error("config.yml missing")
    }
    pipeline()
  })
})
