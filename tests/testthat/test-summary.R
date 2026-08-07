test_that("warnings and errors are auto-recorded; info/success are not", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Task")
    log_info("fyi")
    log_success("ok")
    log_warn("careful")
    log_error("nope")
  }
  capture.output(f())

  statuses <- vapply(the$summary, function(e) e$status, character(1))
  expect_setequal(statuses, c("warning", "error"))
})

test_that("summary = FALSE drops a warning; summary = TRUE pins an info line", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("Task")
    log_warn("noisy", summary = FALSE)
    log_info("pinned", summary = TRUE)
  }
  capture.output(f())

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$status, "info")
  expect_identical(the$summary[[1]]$msg, "pinned")
})

test_that("an interrupted step is recorded with no handler installed", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$status, "interrupted")
  expect_identical(the$summary[[1]]$path, c("Outer", "Inner"))
})

test_that("under with_logging(), one failure collapses to a single entry", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  run <- function() with_logging({ outer() }, summary = FALSE)
  capture.output(tryCatch(run(), error = function(e) NULL))

  expect_length(the$summary, 1L)
  expect_identical(the$summary[[1]]$kind, "leaf")
  expect_identical(the$summary[[1]]$status, "error")
  expect_match(the$summary[[1]]$msg, "boom")
  expect_identical(the$summary[[1]]$path, c("Outer", "Inner"))
})

test_that("independent sibling failures are both kept", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  one <- function() {
    log_step("One")
    log_error("first")
  }
  two <- function() {
    log_step("Two")
    log_error("second")
  }
  driver <- function() {
    one()
    two()
  }
  capture.output(driver())

  msgs <- vapply(the$summary, function(e) e$msg, character(1))
  expect_setequal(msgs, c("first", "second"))
})

test_that("logtree_summary() prints a header with counts and returns entries invisibly", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w1")
    log_error("e1")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(gap = 0, rule = FALSE))
  expect_match(out[[1]], "^Summary: ")
  expect_match(out[[1]], "1 error")
  expect_match(out[[1]], "1 warning")
  expect_length(res, 2L)
  expect_false(withVisible(logtree_summary())$visible)
})

test_that("a leaf message joins its breadcrumb with ' > ' as the terminal node", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  pipeline <- function() {
    log_step("Extract")
    log_warn("2 rows dropped")
    log_step("Transform")
    log_error("schema mismatch")
    log_info("42 records staged", summary = TRUE)
  }
  capture.output(pipeline())

  out <- capture.output(logtree_summary())
  expect_true(any(grepl("Extract > 2 rows dropped", out, fixed = TRUE)))
  expect_true(any(grepl("Extract > Transform > schema mismatch", out, fixed = TRUE)))
  expect_true(any(grepl("Extract > Transform > 42 records staged", out, fixed = TRUE)))
})

test_that("depth keeps only the trailing N breadcrumb nodes (message counts)", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  pipeline <- function() {
    log_step("Extract")
    log_step("Transform")
    log_error("schema mismatch")
  }
  capture.output(pipeline())

  out1 <- capture.output(logtree_summary(depth = 1))
  expect_true(any(grepl("schema mismatch", out1, fixed = TRUE)))
  expect_false(any(grepl("Transform > schema mismatch", out1, fixed = TRUE)))

  out2 <- capture.output(logtree_summary(depth = 2))
  expect_true(any(grepl("Transform > schema mismatch", out2, fixed = TRUE)))
  expect_false(any(grepl("Extract > Transform", out2, fixed = TRUE)))

  # depth beyond the crumb length is a no-op (full path shown).
  out9 <- capture.output(logtree_summary(depth = 9))
  expect_true(any(grepl("Extract > Transform > schema mismatch", out9, fixed = TRUE)))
})

test_that("depth clips a step (non-leaf) entry's path too, keeping the outcome word", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))

  out <- capture.output(logtree_summary(depth = 1))
  expect_true(any(grepl("Inner  did not complete", out, fixed = TRUE)))
  expect_false(any(grepl("Outer > Inner", out, fixed = TRUE)))
})

test_that("depth returns the full path in the entries regardless of printing", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("A")
    log_step("B")
    log_error("x")
  }
  capture.output(f())

  res <- capture.output(entries <- logtree_summary(depth = 1))
  expect_identical(entries[[1]]$path, c("A", "B"))
})

test_that("depth rejects non-positive or non-integer values", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_error(logtree_summary(depth = 0), "positive whole number")
  expect_error(logtree_summary(depth = -1), "positive whole number")
  expect_error(logtree_summary(depth = 1.5), "positive whole number")
  expect_error(logtree_summary(depth = "2"), "positive whole number")
})

test_that("an empty summary prints nothing-to-report", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_success("done")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(gap = 0, rule = FALSE))
  expect_match(out, "nothing to report")
  expect_length(res, 0L)
})

test_that("logtree_reset() clears the summary buffer", {
  logtree_reset()
  withr::defer(logtree_reset())

  f <- function() {
    log_step("T")
    log_warn("w")
  }
  capture.output(f())
  expect_gt(length(the$summary), 0L)

  logtree_reset()
  expect_length(the$summary, 0L)
})

test_that("filter filters the digest to a single status", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w1")
    log_error("e1")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(filter = "error", gap = 0, rule = FALSE))
  expect_match(out[[1]], "1 error")
  expect_false(any(grepl("warning", out)))
  expect_length(res, 1L)
  expect_identical(res[[1]]$status, "error")
})

test_that("filter accepts a vector of statuses", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))
  g <- function() {
    log_step("T2")
    log_warn("careful")
  }
  capture.output(g())

  res <- logtree_summary(filter = c("warning", "interrupted"))
  statuses <- vapply(res, function(e) e$status, character(1))
  expect_setequal(statuses, c("interrupted", "warning"))
})

test_that("filter with no matching status reports nothing", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    log_step("T")
    log_warn("w")
  }
  capture.output(f())

  out <- capture.output(res <- logtree_summary(filter = "error", gap = 0, rule = FALSE))
  expect_match(out, "nothing to report")
  expect_length(res, 0L)
})

test_that("logtree_summary() prints outcome words for non-leaf step entries", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # A step that elevates via a summary = FALSE leaf records a *step* entry (the
  # leaf itself is dropped), so logtree_summary() renders the switch()-mapped
  # outcome word rather than a message.
  warned <- function() {
    log_step("Warned")
    log_warn("quiet", summary = FALSE)
  }
  failed <- function() {
    log_step("Failed")
    log_error("quiet", summary = FALSE)
  }
  capture.output({ warned(); failed() })

  out <- capture.output(logtree_summary())
  expect_true(any(grepl("Warned  completed with warning", out)))
  expect_true(any(grepl("Failed  failed", out)))
})

# --- Divider layout --------------------------------------------------------

# One warning, so every divider test below has a digest to print.
local_warned_run <- function() {
  f <- function() {
    log_step("Task")
    log_warn("careful")
  }
  capture.output(f())
  invisible(NULL)
}

test_that("the digest is set off by a blank gap and a rule carrying the header", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  out <- cli::ansi_strip(capture.output(logtree_summary()))
  expect_identical(out[[1]], "")
  expect_match(out[[2]], "Summary: 1 warning")
  # The header is the rule's label, not a line of its own.
  expect_length(grep("^Summary: ", out), 0L)
})

test_that("gap sets the number of blank lines above the digest", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  out0 <- cli::ansi_strip(capture.output(logtree_summary(gap = 0)))
  expect_false(identical(out0[[1]], ""))

  out2 <- cli::ansi_strip(capture.output(logtree_summary(gap = 2)))
  expect_identical(out2[1:2], c("", ""))
  expect_match(out2[[3]], "Summary: 1 warning")
})

test_that("rule = FALSE keeps the plain header line, gap still applies", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  out <- cli::ansi_strip(capture.output(logtree_summary(rule = FALSE)))
  expect_identical(out[[1]], "")
  expect_identical(out[[2]], "Summary: 1 warning")
})

test_that("NULL means 'take the theme's value', not 'off'", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  out <- cli::ansi_strip(capture.output(logtree_summary(gap = NULL, rule = NULL)))
  expect_identical(out[[1]], "")
  expect_match(out[[2]], "Summary: 1 warning")
})

test_that("a character rule titles the divider and keeps the header below it", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  out <- cli::ansi_strip(capture.output(
    logtree_summary(gap = 0, rule = "Run report")
  ))
  expect_match(out[[1]], "Run report")
  expect_identical(out[[2]], "Summary: 1 warning")
})

test_that("the divider defaults come from the theme's summary slot", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  logtree_theme(list(summary = list(gap = 0, rule = FALSE)))
  out <- cli::ansi_strip(capture.output(logtree_summary()))
  expect_identical(out[[1]], "Summary: 1 warning")

  # An explicit argument overrides the theme for that one call.
  out2 <- cli::ansi_strip(capture.output(logtree_summary(gap = 1, rule = TRUE)))
  expect_identical(out2[[1]], "")
  expect_match(out2[[2]], "-- Summary: 1 warning --")
})

test_that("a theme with no summary/crumb slots falls back to the defaults", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  # A hand-rolled preset predating these slots must still render.
  the$theme[["summary"]] <- NULL
  the$theme[["crumb"]]   <- NULL
  out <- cli::ansi_strip(capture.output(logtree_summary()))
  expect_identical(out[[1]], "")
  expect_match(out[[2]], "Summary: 1 warning")
  expect_identical(out[[3]], "! Task > careful")
})

test_that("the rule's line character comes from the theme", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_warned_run()

  expect_identical(glyphs_ascii$summary$line, "-")
  expect_identical(glyphs_unicode$summary$line, 1L)

  out <- cli::ansi_strip(capture.output(logtree_summary(gap = 0)))
  expect_match(out[[1]], "---")

  logtree_theme(list(summary = list(line = "=")))
  out2 <- cli::ansi_strip(capture.output(logtree_summary(gap = 0)))
  expect_match(out2[[1]], "===")
})

# --- Breadcrumb ------------------------------------------------------------

test_that("format_crumb joins nodes with the theme's separator", {
  theme <- list(crumb = list(glyph = " / ", color = NULL, path_color = NULL))
  expect_identical(
    format_crumb(c("A", "B", "msg"), plain_last = TRUE, theme = theme),
    "A / B / msg"
  )
  expect_identical(format_crumb(character(0), theme = theme), "")
  expect_identical(format_crumb("solo", theme = theme), "solo")
})

test_that("format_crumb emphasises the path but not a leaf's message", {
  testthat::local_reproducible_output(crayon = TRUE)
  theme <- list(crumb = list(glyph = " > ", color = "dim", path_color = "bold"))

  styled <- format_crumb(c("A", "msg"), plain_last = TRUE, theme = theme)
  expect_identical(cli::ansi_strip(styled), "A > msg")
  expect_true(cli::ansi_has_any(styled))
  # The path node is styled, the terminal message is left bare.
  expect_true(endsWith(styled, "msg"))
  # Step entries have no message, so every node is emphasised.
  expect_false(endsWith(format_crumb(c("A", "B"), theme = theme), "B"))

  # color = FALSE strips all of it.
  expect_identical(
    format_crumb(c("A", "msg"), plain_last = TRUE, theme = theme, color = FALSE),
    "A > msg"
  )
})

test_that("the breadcrumb separator is customisable through the theme", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  pipeline <- function() {
    log_step("Extract")
    log_step("Transform")
    log_error("schema mismatch")
  }
  capture.output(pipeline())

  logtree_theme(list(crumb = list(glyph = " -> ")))
  out <- cli::ansi_strip(capture.output(logtree_summary(gap = 0, rule = FALSE)))
  expect_true(any(grepl("Extract -> Transform -> schema mismatch", out, fixed = TRUE)))
})

test_that("the built-in presets carry crumb and summary slots", {
  for (preset in list(glyphs_unicode, glyphs_ascii, glyphs_emoji)) {
    expect_named(preset$crumb, c("glyph", "color", "path_color"))
    expect_named(preset$summary, c("gap", "rule", "line"))
  }
  # The unicode/emoji presets emphasise the path; ascii stays colorless like
  # every other slot of that preset.
  expect_identical(glyphs_unicode$crumb$path_color, "bold")
  expect_null(glyphs_ascii$crumb$path_color)
})

test_that("gap and rule reject malformed values", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_error(logtree_summary(gap = -1), "non-negative whole number")
  expect_error(logtree_summary(gap = 1.5), "non-negative whole number")
  expect_error(logtree_summary(gap = "1"), "non-negative whole number")
  expect_error(logtree_summary(gap = NA), "non-negative whole number")
  expect_error(logtree_summary(rule = NA), "TRUE, FALSE, or a single title")
  expect_error(logtree_summary(rule = c("a", "b")), "TRUE, FALSE, or a single title")
  expect_error(logtree_summary(rule = 1), "TRUE, FALSE, or a single title")
})

test_that("logtree_summary() reports an interrupted step as 'did not complete'", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  inner <- function() {
    log_step("Inner")
    stop("boom")
  }
  outer <- function() {
    log_step("Outer")
    inner()
  }
  capture.output(tryCatch(outer(), error = function(e) NULL))

  out <- capture.output(logtree_summary())
  expect_true(any(grepl("did not complete", out)))
})
