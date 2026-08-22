at <- function(x) as.POSIXct(x, tz = "UTC")

local_timestamp <- function(format = "%H:%M:%S", ..., envir = parent.frame()) {
  logtree_theme(list(timestamp = utils::modifyList(list(format = format),
                                                   list(...))))
  withr::defer(logtree_theme(list(timestamp = list(format = NULL))),
               envir = envir)
}

test_that("no preset carries a timestamp, so default output is unchanged", {
  for (name in theme_presets) {
    expect_null(timestamp_format(theme_preset(name)),
                info = paste("preset:", name))
  }
})

test_that("a formatter with no stamp renders exactly as before", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_timestamp("%H:%M:%S")

  # The column is a property of the line, not of the theme alone: a line with
  # no event time behind it (the digest) carries no column even with a format
  # set.
  expect_equal(format_leaf("info", "a line", 1L), "|- i a line")
})

test_that("the column is prefixed to every line kind", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_timestamp("%H:%M:%S")

  stamp <- at("2026-01-02 03:04:05")
  entry <- list(id = 1L, parent_id = 0L, kind = "step", label = "Step",
                depth = 1L, status = "running", elapsed = 1.5)
  group <- list(id = 1L, parent_id = 0L, kind = "group", name = "Batch",
                depth = 1L, status = "running", elapsed = 1.5)

  expect_match(format_open(entry, stamp = stamp), "^03:04:05 > Step$")
  expect_match(format_close(entry, stamp = stamp), "^03:04:05 \\|- \\+ Done")
  expect_match(format_group_header(group, stamp = stamp), "^03:04:05 < Batch >$")
  expect_match(format_leaf("info", "a line", 1L, stamp = stamp),
               "^03:04:05 \\|- i a line$")
})

test_that("a glyph-only close line still gets its timestamp", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_timestamp("%H:%M:%S")
  # No close word and no elapsed time: the message is empty, but the timestamp
  # is a column of the line rather than part of the message.
  logtree_theme(list(done = list(text = ""), elapsed = list(show = FALSE)))
  withr::defer(logtree_theme("ascii"))

  entry <- list(id = 1L, parent_id = 0L, kind = "step", label = "Step",
                depth = 1L, status = "running", elapsed = 1.5)
  expect_equal(format_close(entry, stamp = at("2026-01-02 03:04:05")),
               "03:04:05 |- +")
})

test_that("a variable-width format is padded to a fixed column", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  # Full month name: 5 characters in March, 8 in December. A bare day-of-month
  # ("%-d") would say the same thing more directly, but the "-" padding flag is
  # a glibc extension -- macOS and Windows render it literally -- and a test
  # that only holds on Linux is not testing the padding.
  withr::local_locale(c(LC_TIME = "C"))
  local_timestamp("%B")

  narrow <- format_leaf("info", "x", 1L, stamp = at("2026-03-05 10:00:00"))
  wide   <- format_leaf("info", "x", 1L, stamp = at("2026-12-25 10:00:00"))

  # Same width, so the tree does not shear between one line and the next.
  expect_equal(cli::ansi_nchar(narrow, type = "width"),
               cli::ansi_nchar(wide, type = "width"))
  expect_match(narrow, "^March    \\|- i x$")
  expect_match(wide,   "^December \\|- i x$")
})

test_that("a format wider than the reference instant is clipped, not left to shear", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_timestamp("%H:%M:%S")

  a <- format_leaf("info", "x", 1L, stamp = at("2026-01-02 03:04:05"))
  b <- format_leaf("info", "x", 1L, stamp = at("2026-01-02 23:59:59"))
  expect_equal(cli::ansi_nchar(a, type = "width"),
               cli::ansi_nchar(b, type = "width"))
})

test_that("the tree lines up under a timestamp exactly as it does without one", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  # Elapsed times would otherwise differ between the two runs below, and the
  # point here is the columns, not the clock.
  freeze_clock(0)

  tree <- function() {
    f <- function() {
      log_step("Pipeline")
      g <- function() {
        log_step("Load data")
        log_info("1200 rows")
      }
      g()
    }
    capture.output(invisible(f()))
  }

  plain <- tree()
  local_timestamp("%H:%M:%S")
  logtree_reset()
  stamped <- tree()

  expect_equal(length(plain), length(stamped))
  # Every stamped line is the plain line with one constant-width column in
  # front of it.
  expect_equal(substring(stamped, 10L), plain)
  expect_true(all(grepl("^[0-9]{2}:[0-9]{2}:[0-9]{2} ", stamped)))
})

test_that("wrapping loses exactly the timestamp column from its budget", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  withr::defer(logtree_theme("ascii"))

  msg <- "a leaf message long enough that it has to wrap somewhere sensible"

  logtree_theme(wrap = 60)
  plain <- format_leaf("info", msg, 1L)
  local_timestamp("%H:%M:%S")
  stamped <- format_leaf("info", msg, 1L, stamp = at("2026-01-02 03:04:05"))

  # Nine columns fewer to play with ("03:04:05" plus its space), so the same
  # message at the same width breaks earlier.
  logtree_theme(wrap = 60 - 9)
  narrower <- format_leaf("info", msg, 1L)
  expect_equal(sub("^[^ ]+ ", "", strsplit(stamped, "\n")[[1]][[1]]),
               strsplit(narrower, "\n")[[1]][[1]])
  expect_false(identical(plain, narrower))
})

test_that("continuation rows carry a blank column, never a repeated time", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  withr::defer(logtree_theme("ascii"))
  logtree_theme(wrap = 40)
  local_timestamp("%H:%M:%S")

  lines <- strsplit(
    format_leaf("info", "a leaf message long enough to wrap onto a second row",
                1L, stamp = at("2026-01-02 03:04:05")),
    "\n", fixed = TRUE
  )[[1]]

  expect_gt(length(lines), 1L)
  expect_match(lines[[1]], "^03:04:05 ")
  # One event happened once: the rest of its rows get spaces of the same width.
  for (line in lines[-1]) {
    expect_match(line, "^         ")
    expect_false(grepl("03:04:05", line, fixed = TRUE))
  }
})

test_that("a wrapped group header blanks the timestamp column too", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  withr::defer(logtree_theme("ascii"))
  logtree_theme(wrap = 34)
  local_timestamp("%H:%M:%S")

  group <- list(id = 1L, parent_id = 0L, kind = "group",
                name = "a group name long enough to wrap onto another row",
                depth = 1L, status = "running")
  lines <- strsplit(format_group_header(group, stamp = at("2026-01-02 03:04:05")),
                    "\n", fixed = TRUE)[[1]]

  expect_gt(length(lines), 1L)
  expect_match(lines[[1]], "^03:04:05 ")
  expect_match(lines[[2]], "^         ")
})

test_that("a live run stamps every line, digest lines excepted", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_timestamp("%H:%M:%S")
  freeze_wall_clock("2026-01-02 03:04:05")

  f <- function() {
    with_logging({
      log_step("Step")
      log_warn("coerced 3 rows")
    })
  }
  out <- capture.output(invisible(f()))
  # Tree lines and the run-summary line: all live, all stamped.
  expect_true(all(grepl("^03:04:05 ", out)))

  # The digest replays events that already happened, so stamping it with the
  # time it was printed would be a lie. It carries no column.
  digest <- capture.output(logtree_summary())
  expect_false(any(grepl("03:04:05", digest, fixed = TRUE)))
})

test_that("a text sink follows the console's timestamp by default", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_timestamp("%H:%M:%S")
  freeze_wall_clock("2026-01-02 03:04:05")

  path <- tempfile()
  logtree_sink_file(path, format = "text")
  f <- function() log_info("recorded")
  invisible(capture.output(f()))

  expect_match(readLines(path)[[1]], "^03:04:05 i recorded$")
})

test_that("a text sink can pin its own timestamp, or pin it off", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  freeze_wall_clock("2026-01-02 03:04:05")

  # Console column off; the file wants one anyway.
  pinned <- tempfile()
  logtree_sink_file(pinned, format = "text", timestamp = "%H:%M")
  # Console column on; this file does not want one.
  off <- tempfile()
  logtree_sink_file(off, format = "text", timestamp = FALSE)
  local_timestamp("%H:%M:%S")

  f <- function() log_info("recorded")
  out <- capture.output(invisible(f()))

  expect_match(out[[1]], "^03:04:05 ")
  expect_match(readLines(pinned)[[1]], "^03:04 i recorded$")
  expect_match(readLines(off)[[1]], "^i recorded$")
})

test_that("timestamp = TRUE on a sink means a date as well as a time", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  freeze_wall_clock("2026-01-02 03:04:05")

  path <- tempfile()
  logtree_sink_file(path, format = "text", timestamp = TRUE)
  f <- function() log_info("recorded")
  invisible(capture.output(f()))

  expect_match(readLines(path)[[1]], "^2026-01-02 03:04:05 i recorded$")
})

test_that("logtree_sink_file rejects a nonsense timestamp", {
  expect_error(logtree_sink_file(tempfile(), timestamp = 12),
               "strftime format string")
  expect_error(logtree_sink_file(tempfile(), timestamp = c("%H", "%M")),
               "strftime format string")
})

test_that("the timestamp is styled by its slot's colour", {
  logtree_reset()
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", wrap = FALSE,
                overrides = list(timestamp = list(format = "%H:%M:%S",
                                                  color = "red")))

  withr::with_options(list(cli.num_colors = 256L), {
    line <- format_leaf("info", "x", 1L, stamp = at("2026-01-02 03:04:05"))
    expect_true(grepl("\033[31m03:04:05\033[39m", line, fixed = TRUE))
    # Colour off (file sinks) renders the same text with no escapes.
    plain <- format_leaf("info", "x", 1L, stamp = at("2026-01-02 03:04:05"),
                         color = FALSE)
    expect_false(grepl("\033", plain, fixed = TRUE))
  })
})

test_that("an empty or non-string format reads as off", {
  expect_null(timestamp_format(list(timestamp = list(format = ""))))
  expect_null(timestamp_format(list(timestamp = list(format = NA_character_))))
  expect_null(timestamp_format(list(timestamp = list(format = 42))))
  expect_null(timestamp_format(list()))
  expect_equal(timestamp_format(list(timestamp = list(format = "%H"))), "%H")
})
