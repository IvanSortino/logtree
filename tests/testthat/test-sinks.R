test_that("logtree_sink registers a sink that receives every event", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  seen <- list()
  h <- logtree_sink(function(event) seen[[length(seen) + 1L]] <<- event)
  expect_type(h, "character")

  f <- function() {
    log_step("Step")
    log_info("a line")
  }
  invisible(capture.output(f()))

  kinds <- vapply(seen, function(e) e$kind, character(1))
  expect_equal(kinds, c("open", "leaf", "close"))
})

test_that("logtree_sinks lists ids in firing order, console first", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  expect_equal(logtree_sinks(), "console")
  a <- logtree_sink(function(event) invisible(NULL))
  b <- logtree_sink(function(event) invisible(NULL))
  expect_equal(logtree_sinks(), c("console", a, b))
})

test_that("sinks fire in registration order, and removal does not disturb it", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  order <- character(0)
  a <- logtree_sink(function(event) order <<- c(order, "a"))
  b <- logtree_sink(function(event) order <<- c(order, "b"))
  c_ <- logtree_sink(function(event) order <<- c(order, "c"))

  invisible(capture.output(log_info("one")))
  expect_equal(order, c("a", "b", "c"))

  # Take the middle one out: the survivors keep their relative order, and a
  # sink registered afterwards goes to the end rather than into the gap.
  logtree_sink_remove(b)
  d <- logtree_sink(function(event) order <<- c(order, "d"))
  order <- character(0)
  invisible(capture.output(log_info("two")))
  expect_equal(order, c("a", "c", "d"))
})

test_that("logtree_sink_remove is a no-op for ids that are not registered", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  before <- logtree_sinks()
  expect_silent(removed <- logtree_sink_remove("no-such-sink"))
  expect_length(removed, 0L)
  expect_equal(logtree_sinks(), before)
})

test_that("logtree_sink_remove returns the removed functions, keyed by id", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  fn <- function(event) invisible(NULL)
  h  <- logtree_sink(fn)
  removed <- logtree_sink_remove(h)

  expect_named(removed, h)
  expect_identical(removed[[h]], fn)
})

test_that("the console sink can be removed and registered again", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  saved <- logtree_sink_remove("console")
  expect_named(saved, "console")
  expect_false("console" %in% logtree_sinks())

  f <- function() log_info("silence")
  expect_equal(capture.output(f()), character(0))

  # Back it comes -- under a fresh id, and so at the end of the firing order.
  logtree_sink(saved[["console"]])
  out <- capture.output(f())
  expect_match(out, "i silence")
})

test_that("logtree_sink rejects a non-function", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  expect_error(logtree_sink("not a function"), "must be a function")
})

test_that("logtree_sink_remove rejects a non-character id", {
  expect_error(logtree_sink_remove(1L), "character vector")
})

test_that("a throwing sink does not stop the others, and warns once", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  after <- 0L
  logtree_sink(function(event) stop("sink is broken"))
  logtree_sink(function(event) after <<- after + 1L)

  f <- function() log_info("one")
  expect_warning(capture.output(f()), "logtree sink '.*' threw and was skipped")
  # The sink registered after the broken one still saw the event.
  expect_equal(after, 1L)

  # Once per sink: the second event is silent even though the sink still throws.
  g <- function() log_info("two")
  expect_silent(capture.output(g()))
  expect_equal(after, 2L)
})

test_that("the broken-sink warning is armed again by logtree_reset", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  logtree_sink(function(event) stop("sink is broken"))
  f <- function() log_info("one")
  expect_warning(capture.output(f()))

  logtree_reset()
  expect_warning(capture.output(f()))
})

test_that("removing a trace sink takes its capture back with it", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  expect_false(trace_enabled())
  h <- logtree_sink_file(tempfile(), format = "text", trace = TRUE)
  expect_true(trace_enabled())
  logtree_sink_remove(h)
  expect_false(trace_enabled())
})

test_that("logtree_sink_file returns a handle that unregisters the file", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  path <- tempfile()
  h <- logtree_sink_file(path, format = "text")
  f <- function() log_info("recorded")
  invisible(capture.output(f()))

  logtree_sink_remove(h)
  g <- function() log_info("not recorded")
  invisible(capture.output(g()))

  lines <- readLines(path)
  expect_true(any(grepl("recorded", lines, fixed = TRUE)))
  expect_false(any(grepl("not recorded", lines, fixed = TRUE)))
})
