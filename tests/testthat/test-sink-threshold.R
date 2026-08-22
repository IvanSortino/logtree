test_that("a sink's own threshold does not move the console's", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  logtree_threshold("info")
  path <- tempfile()
  logtree_sink_file(path, format = "text", threshold = "debug")

  f <- function() {
    log_step("Step")
    log_debug("debug line")
    log_info("info line")
  }
  out <- capture.output(invisible(f()))

  # Console keeps the global level; the file records everything.
  expect_false(any(grepl("debug line", out)))
  expect_true(any(grepl("info line", out)))
  lines <- readLines(path)
  expect_true(any(grepl("debug line", lines)))
  expect_true(any(grepl("info line", lines)))
})

test_that("a sink can be quieter than the console as well as louder", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  logtree_threshold("info")
  h <- logtree_sink_memory(threshold = "error")

  f <- function() {
    log_info("info line")
    log_warn("warn line")
    log_error("error line")
  }
  out <- capture.output(invisible(f()))

  expect_equal(logtree_sink_memory_events(h)$label, "error line")
  expect_true(any(grepl("info line", out)))
})

test_that("thresholds are per sink and do not leak between them", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  logtree_threshold("info")
  loud  <- logtree_sink_memory(threshold = "debug")
  quiet <- logtree_sink_memory(threshold = "warn")
  plain <- logtree_sink_memory()   # follows the global level

  f <- function() {
    log_debug("d")
    log_info("i")
    log_warn("w")
  }
  invisible(capture.output(f()))

  expect_equal(logtree_sink_memory_events(loud)$label,  c("d", "i", "w"))
  expect_equal(logtree_sink_memory_events(quiet)$label, "w")
  expect_equal(logtree_sink_memory_events(plain)$label, c("i", "w"))
})

test_that("a sink with no threshold follows logtree_threshold as it moves", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  h <- logtree_sink_memory()
  logtree_threshold("info")
  f <- function() log_debug("before")
  invisible(capture.output(f()))
  expect_equal(nrow(logtree_sink_memory_events(h)), 0L)

  logtree_threshold("debug")
  g <- function() log_debug("after")
  invisible(capture.output(g()))
  expect_equal(logtree_sink_memory_events(h)$label, "after")
})

test_that("step open/close lines are never gated by a sink threshold", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  h <- logtree_sink_memory(threshold = "error")
  f <- function() {
    log_step("Always recorded")
    log_info("gated out")
  }
  invisible(capture.output(f()))

  events <- logtree_sink_memory_events(h)
  expect_equal(events$level, c("open", "close"))
  expect_equal(unique(events$label), "Always recorded")
})

test_that("logtree_sink rejects an unknown threshold", {
  expect_error(logtree_sink(function(event) NULL, threshold = "chatty"))
  expect_error(logtree_sink(function(event) NULL, threshold = 1L), "must be NULL or one of")
})

test_that("a threshold is case-insensitive, like logtree_threshold()", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_reset_verbosity()

  logtree_threshold("info")
  h <- logtree_sink_memory(threshold = "DEBUG")
  f <- function() log_debug("recorded anyway")
  invisible(capture.output(f()))
  expect_equal(logtree_sink_memory_events(h)$label, "recorded anyway")
})

# --- The digest, now that verbosity is a rendering gate only -----------------

test_that("a threshold-suppressed warning still reaches the digest", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_threshold("error")
  f <- function() {
    log_step("Step")
    log_warn("this text is suppressed")
  }
  out <- capture.output(invisible(f()))
  expect_false(any(grepl("this text is suppressed", out)))

  # Hidden from the tree, but the run still knows it happened -- the same
  # principle that already elevates the step's close glyph.
  entries <- NULL
  invisible(capture.output(entries <- logtree_summary()))
  msgs <- vapply(entries, function(e) if (is.null(e$msg)) "" else e$msg, character(1))
  expect_true("this text is suppressed" %in% msgs)
})

test_that("a suppressed line pinned with summary = TRUE is recorded too", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  logtree_threshold("error")
  f <- function() {
    log_step("Step")
    log_info("pinned even though hidden", summary = TRUE)
  }
  invisible(capture.output(f()))

  entries <- NULL
  invisible(capture.output(entries <- logtree_summary()))
  msgs <- vapply(entries, function(e) if (is.null(e$msg)) "" else e$msg, character(1))
  expect_true("pinned even though hidden" %in% msgs)
})

test_that("summary = FALSE still keeps a warning out of the digest", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()

  f <- function() {
    log_step("Step")
    log_warn("not for the digest", summary = FALSE)
  }
  invisible(capture.output(f()))

  entries <- NULL
  invisible(capture.output(entries <- logtree_summary()))
  msgs <- vapply(entries, function(e) if (is.null(e$msg)) "" else e$msg, character(1))
  expect_false("not for the digest" %in% msgs)
})

test_that("a leaf nobody wants is never built, so it costs no call-site walk", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)
  local_reset_verbosity()
  local_reset_sinks()

  logtree_threshold("info")
  # Nothing admits a debug leaf, and summary = FALSE keeps the digest out of it.
  before <- the$next_id
  f <- function() log_debug("cache miss", summary = FALSE)
  invisible(capture.output(f()))
  expect_equal(the$next_id, before)
})

# --- Richer JSON -------------------------------------------------------------

test_that("the json sink writes an ISO-8601 timestamp", {
  skip_if_not_installed("jsonlite")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  freeze_wall_clock("2026-01-02 03:04:05")

  path <- tempfile(fileext = ".ndjson")
  logtree_sink_file(path, format = "json")
  f <- function() log_info("one line")
  invisible(capture.output(f()))

  rec <- jsonlite::fromJSON(readLines(path)[[1]])
  expect_match(rec$ts, "^2026-01-02T[0-9]{2}:04:05\\.000[+-][0-9]{4}$")
  # And it round-trips back to the instant that was stamped.
  expect_equal(
    as.numeric(as.POSIXct(rec$ts, format = "%Y-%m-%dT%H:%M:%OS%z", tz = "UTC")),
    as.numeric(as.POSIXct("2026-01-02 03:04:05", tz = "UTC"))
  )
})

test_that("the json sink carries a run id, stable within a run", {
  skip_if_not_installed("jsonlite")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  path <- tempfile(fileext = ".ndjson")
  logtree_sink_file(path, format = "json")

  f <- function() {
    with_logging({
      log_step("Step")
      log_info("one line")
    }, summary = FALSE)
  }
  invisible(capture.output(f()))
  first <- vapply(readLines(path), function(l) jsonlite::fromJSON(l)$run_id,
                  character(1), USE.NAMES = FALSE)
  expect_length(unique(first), 1L)
  expect_true(nzchar(unique(first)))
})

test_that("each with_logging() call gets its own run id", {
  skip_if_not_installed("jsonlite")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  path <- tempfile(fileext = ".ndjson")
  logtree_sink_file(path, format = "json")

  f <- function() with_logging(log_info("a line"), summary = FALSE)
  invisible(capture.output(f()))
  invisible(capture.output(f()))

  ids <- vapply(readLines(path), function(l) jsonlite::fromJSON(l)$run_id,
                character(1), USE.NAMES = FALSE)
  expect_length(ids, 2L)
  expect_false(identical(ids[[1]], ids[[2]]))
})

test_that("a run id is generated without disturbing the RNG stream", {
  logtree_reset()
  withr::defer(logtree_reset())

  set.seed(42)
  expected <- runif(1)

  set.seed(42)
  invisible(new_run_id())
  invisible(new_run_id())
  expect_equal(runif(1), expected)
})
