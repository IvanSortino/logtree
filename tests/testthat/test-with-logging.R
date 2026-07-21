# Note: log_step() calls inside a with_logging({...}) block attach their
# close handler to whatever frame *lexically* encloses that block (R's
# promise semantics -- the block is evaluated in the environment where it
# was written, not inside with_logging()'s own frame). In realistic usage
# with_logging({...}) is a function's entire body, so that frame and "when
# with_logging() returns" coincide. These tests wrap every call in such a
# function so the close fires before we inspect state/output, matching how
# the package is actually meant to be used.

test_that("with_logging rethrows and never swallows the error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Fetching articles")
      log_step("Parsing")
      stop("model timeout after 30s")
    })
  }

  expect_error(f(), "model timeout after 30s")
})

test_that("with_logging flags every open ancestor as failed, not just the innermost", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Fetching articles")
      log_step("Parsing")
      stop("model timeout after 30s")
    })
  }

  out <- capture.output(invisible(tryCatch(f(), error = function(e) NULL)))

  # Both step close lines (Parsing = inner, Fetching articles = outer)
  # render the error glyph, not just the one that literally threw.
  expect_length(grep("x Done", out), 2)
})

test_that("with_logging leaves the stack empty after an error", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Fetching articles")
      stop("boom")
    })
  }

  capture.output(invisible(tryCatch(f(), error = function(e) NULL)))
  expect_length(the$stack, 0)
})

test_that("with_logging prints a summary line by default, suppressible via summary = FALSE", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f_default <- function() {
    with_logging({
      log_step("ok step")
    })
  }
  out_with_summary <- capture.output(invisible(f_default()))
  expect_true(any(grepl("Run complete", out_with_summary)))

  logtree_reset()
  f_no_summary <- function() {
    with_logging({
      log_step("ok step")
    }, summary = FALSE)
  }
  out_without_summary <- capture.output(invisible(f_no_summary()))
  expect_false(any(grepl("Run complete", out_without_summary)))
})
