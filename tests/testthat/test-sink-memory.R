test_that("the memory sink collects one row per event, oldest first", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  h <- logtree_sink_memory()
  f <- function() {
    log_step("Load data")
    log_info("1200 rows")
    log_warn("coerced 3 rows")
  }
  invisible(capture.output(f()))

  events <- logtree_sink_memory_events(h)
  expect_s3_class(events, "data.frame")
  expect_equal(events$level, c("open", "leaf", "leaf", "close"))
  expect_equal(events$label,
               c("Load data", "1200 rows", "coerced 3 rows", "Load data"))
  expect_equal(events$status, c("step", "info", "warning", "warning"))
})

test_that("the memory sink's columns match the JSON sink's schema and types", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  h <- logtree_sink_memory()
  f <- function() log_step("Step")
  invisible(capture.output(f()))

  events <- logtree_sink_memory_events(h)
  expect_named(events, names(record_proto()))
  expect_s3_class(events$ts, "POSIXct")
  expect_type(events$level, "character")
  expect_type(events$id, "integer")
  expect_type(events$parent_id, "integer")
  expect_type(events$depth, "integer")
  expect_type(events$label, "character")
  # Numeric even on the rows that have no elapsed time -- an all-missing column
  # must not collapse to logical NA, or a caller's arithmetic breaks on the one
  # run where nothing closed.
  expect_type(events$elapsed, "double")
  expect_true(is.na(events$elapsed[[1]]))
  expect_true(events$elapsed[[2]] >= 0)
  expect_type(events$line, "integer")
})

test_that("an untouched memory sink reads back as zero typed rows", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  h <- logtree_sink_memory()
  events <- logtree_sink_memory_events(h)
  expect_equal(nrow(events), 0L)
  expect_named(events, names(record_proto()))
  expect_type(events$elapsed, "double")
})

test_that("the memory sink records the same time the JSON sink writes", {
  skip_if_not_installed("jsonlite")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  freeze_wall_clock("2026-01-02 03:04:05")

  path <- tempfile(fileext = ".ndjson")
  h <- logtree_sink_memory()
  logtree_sink_file(path, format = "json")

  f <- function() log_info("one line")
  invisible(capture.output(f()))

  from_memory <- logtree_sink_memory_events(h)$ts[[1]]
  from_json   <- jsonlite::fromJSON(readLines(path)[[1]])$ts
  # Stamped once in emit() and handed to both sinks, so they cannot disagree.
  expect_equal(format(from_memory, json_ts_format), from_json)
})

test_that("the memory sink keeps the last `max` events", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  h <- logtree_sink_memory(max = 3)
  f <- function() {
    log_info("one")
    log_info("two")
    log_info("three")
    log_info("four")
    log_info("five")
  }
  invisible(capture.output(f()))

  events <- logtree_sink_memory_events(h)
  expect_equal(nrow(events), 3L)
  expect_equal(events$label, c("three", "four", "five"))
})

test_that("logtree_sink_memory validates `max`", {
  expect_error(logtree_sink_memory(max = 0), "positive number")
  expect_error(logtree_sink_memory(max = "lots"), "positive number")
})

test_that("removing a memory sink drops its buffer", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  h <- logtree_sink_memory()
  f <- function() log_info("one")
  invisible(capture.output(f()))
  expect_equal(nrow(logtree_sink_memory_events(h)), 1L)

  logtree_sink_remove(h)
  expect_error(logtree_sink_memory_events(h), "not a registered memory sink")
})

test_that("logtree_sink_memory_events rejects a non-memory sink id", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  expect_error(logtree_sink_memory_events("console"), "not a registered memory sink")
  expect_error(logtree_sink_memory_events(1L), "single memory sink id")
})

test_that("the memory sink flattens groups the same way the JSON sink does", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  h <- logtree_sink_memory()
  f <- function() {
    g <- function() log_step("Article A", group = c(Batch = "b1"))
    g()
    g2 <- function() log_step("Article B", group = c(Batch = "b1"))
    g2()
  }
  invisible(capture.output(f()))

  events <- logtree_sink_memory_events(h)
  # A group carries `name` where a step carries `label`; the record must not
  # care which.
  group_rows <- events[events$level %in% c("group", "group_close"), ]
  expect_true(nrow(group_rows) >= 1L)
  expect_true(all(group_rows$label == "Batch"))
  expect_equal(group_rows$status[[1]], "group")
})
