test_that("text file sink writes a plain ASCII tree with no ANSI codes", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  path <- tempfile()
  logtree_sink_file(path, format = "text")

  f <- function() {
    with_logging({
      log_step("Fetching articles")
      log_info("Connecting to API")
    }, summary = FALSE)
  }
  invisible(f())

  lines <- readLines(path)
  expect_true(length(lines) >= 3)
  expect_false(any(grepl("\033[", lines, fixed = TRUE)))
  expect_match(lines[1], "^> Fetching articles$")
  expect_match(lines[2], "^\\|- i Connecting to API$")
  expect_match(lines[3], "^\\|- \\+ Done")
})

test_that("text file sink stays plain ASCII even when the console theme is unicode", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode")

  path <- tempfile()
  logtree_sink_file(path, format = "text")

  f <- function() {
    log_step("Step")
  }
  invisible(f())

  lines <- readLines(path)
  expect_match(lines[1], "^> Step$")
  x <- tools::showNonASCIIfile(path)
  expect_length(x, 0)
})

test_that("json sink produces one parseable NDJSON object per event", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  path <- tempfile()
  logtree_sink_file(path, format = "json")

  f <- function() {
    with_logging({
      log_step("Fetching articles")
      log_warn("Retry 1/3 due to timeout")
    }, summary = FALSE)
  }
  invisible(f())

  lines <- readLines(path)
  expect_true(length(lines) >= 3)

  parsed <- lapply(lines, function(l) jsonlite::fromJSON(l))
  for (p in parsed) {
    expect_true(all(c("ts", "level", "id", "parent_id", "depth", "label", "elapsed", "status") %in% names(p)))
  }

  levels <- vapply(parsed, function(p) p$level, character(1))
  expect_equal(levels, c("open", "leaf", "close"))

  statuses <- vapply(parsed, function(p) p$status, character(1))
  expect_equal(statuses, c("step", "warning", "warning"))

  expect_true(is.na(parsed[[1]]$elapsed) || is.null(parsed[[1]]$elapsed))
  expect_true(is.numeric(parsed[[3]]$elapsed))
})

test_that("console and file sinks both fire from the same events", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  path <- tempfile()
  logtree_sink_file(path, format = "text")

  f <- function() {
    log_step("Step")
  }
  console_out <- capture.output(invisible(f()))
  file_out <- readLines(path)

  expect_equal(console_out, file_out)
})
