test_that("a muted run prints nothing to the console", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  f <- function() {
    log_step("Step")
    log_info("info line")
    log_warn("warn line")
  }
  expect_equal(capture.output(invisible(f())), character(0))
})

test_that("muting silences file sinks too, not just the console", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_mute()

  path <- tempfile()
  logtree_sink_file(path, format = "text")
  file.create(path)

  logtree_mute()
  f <- function() {
    log_step("Step")
    log_info("info line")
  }
  invisible(capture.output(f()))

  expect_equal(readLines(path), character(0))
})

test_that("a muted run is still recorded, and logtree_summary() still prints", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  f <- function() {
    log_step("Load data")
    log_warn("coerced 3 rows")
  }
  invisible(capture.output(f()))

  # The digest is a record, not output: it survives the mute, and printing it
  # is something the caller asked for rather than something that happened.
  out <- capture.output(entries <- logtree_summary())
  expect_length(entries, 1L)
  expect_equal(entries[[1]]$msg, "coerced 3 rows")
  expect_true(any(grepl("coerced 3 rows", out)))
})

test_that("muting silences the with_logging() run-summary line", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  f <- function() with_logging(log_info("a line"))
  expect_equal(capture.output(invisible(f())), character(0))
})

test_that("muting does not swallow an error, and the run summary comes back", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  f <- function() {
    with_logging({
      log_step("Step")
      stop("boom")
    })
  }
  expect_equal(capture.output(expect_error(f(), "boom")), character(0))

  logtree_unmute()
  g <- function() with_logging(log_info("a line"))
  out <- capture.output(invisible(g()))
  expect_true(any(grepl("Run complete", out)))
})

test_that("unmuting restores output", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  f <- function() log_info("quiet")
  expect_equal(capture.output(invisible(f())), character(0))

  logtree_unmute()
  g <- function() log_info("loud")
  expect_match(capture.output(invisible(g())), "i loud")
})

test_that("mute/unmute return the previous state invisibly", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_mute()

  logtree_unmute()
  # Invisible, and reporting the state it replaced rather than the new one.
  expect_false(withVisible(logtree_mute())$visible)
  expect_true(logtree_unmute())    # it *was* muted, by the line above
  expect_false(logtree_mute())     # and before that, it was not

  # Which is what makes the save/restore idiom work without assuming.
  was <- logtree_mute()
  expect_true(was)
  if (!was) logtree_unmute()
  expect_true(isTRUE(the$muted))
})

test_that("step bookkeeping is unaffected across a mute/unmute cycle", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  # The stack must still push and pop while muted, or depth desyncs the moment
  # output comes back.
  inner <- function() {
    log_step("Inner")
    log_info("deep line")
  }
  outer <- function() {
    log_step("Outer")
    logtree_mute()
    inner()
    logtree_unmute()
    log_info("visible again")
  }
  out <- capture.output(invisible(outer()))

  expect_length(the$stack, 0L)
  expect_false(any(grepl("deep line", out)))
  # Back at depth 1, under "Outer" -- one connector, not three.
  expect_true(any(grepl("^\\|- i visible again$", out)))
})

test_that("mute is not cleared by logtree_reset", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_mute()

  logtree_mute()
  logtree_reset()
  f <- function() log_info("still quiet")
  expect_equal(capture.output(invisible(f())), character(0))
})

test_that(".onLoad seeds the mute flag from the logtree.silent option", {
  # .onLoad rebuilds theme, verbosity, sinks and run id as well, so snapshot
  # every field it touches and put them all back (see test-onload.R).
  old <- list(theme = the$theme, verbosity = the$verbosity, sinks = the$sinks,
              run_id = the$run_id, muted = the$muted)
  withr::defer({
    the$theme     <- old$theme
    the$verbosity <- old$verbosity
    the$sinks     <- old$sinks
    the$run_id    <- old$run_id
    the$muted     <- old$muted
  })

  withr::with_options(list(logtree.silent = TRUE), .onLoad("lib", "logtree"))
  expect_true(the$muted)

  withr::with_options(list(logtree.silent = NULL), .onLoad("lib", "logtree"))
  expect_false(the$muted)
})
