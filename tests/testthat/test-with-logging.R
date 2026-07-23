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

# -- global = TRUE (persistent top-level handler) -------------------------
#
# globalCallingHandlers() can only be *established* when the condition-handler
# stack is empty, which is never the case inside test_that() (testthat keeps
# handlers on the stack). So the successful install + real firing is exercised
# by debug/15_with_logging_global.R at true top level, not here. These tests
# cover the argument guard, the graceful skip, and the handler action itself
# (global_error_action(), which needs no install).

test_that("global_error_action marks open steps failed and logs the message leaf", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  log_open("Load data")
  out <- capture.output(global_error_action(simpleError("boom"), summary = FALSE))

  expect_equal(the$stack[[1]]$status, "error")
  expect_true(any(grepl("boom", out)))
})

test_that("global_error_action is a no-op when no steps are open", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  out <- capture.output(global_error_action(simpleError("unrelated"), summary = FALSE))

  expect_length(out, 0)
  expect_length(the$stack, 0)
})

test_that("with_logging(global = TRUE) rejects an expr argument", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_error(with_logging(log_info("x"), global = TRUE), "takes no")
})

test_that("with_logging(global = TRUE) errors (fail-fast) when handlers are on the stack", {
  logtree_reset()
  withr::defer(logtree_reset())

  # test_that() keeps condition handlers on the stack, so the (unguarded) global
  # establish is illegal here and must surface R's native error rather than
  # installing. The establish cannot be softened (a tryCatch wrapper is itself a
  # handler and would block it even at a clean top level), so global = TRUE is
  # documented as top-level-only.
  expect_error(with_logging(global = TRUE), "should not be called with handlers")
  expect_false(the$global_installed)
})

test_that("global_error_action prints a 'Run failed' summary when summary = TRUE", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  log_open("Load data")
  # install_global_logging() stamps the$global_start; set it here so the
  # elapsed-time formatting in the summary line has a numeric base to subtract.
  the$global_start <- now()
  out <- capture.output(global_error_action(simpleError("boom"), summary = TRUE))

  expect_true(any(grepl("Run failed", out)))
})

test_that("install_global_logging is idempotent: a second call is a no-op", {
  logtree_reset()
  withr::defer(logtree_reset())

  # Pretend a handler is already installed. The early return must fire BEFORE any
  # globalCallingHandlers() call (which would error under test handlers), proving
  # idempotency without touching the real global handler stack.
  the$global_installed <- TRUE
  withr::defer({ the$global_installed <- FALSE; the$global_prev <- NULL })

  expect_null(install_global_logging(TRUE))
  expect_true(the$global_installed)
})

test_that("mark_open_steps elevates open steps but skips group entries", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # A grouped step pushes a synthetic group entry (kind = "group") plus the step
  # entry, so the loop must `next` past the group and elevate only the step.
  capture.output(log_step("member", group = c(Batch = "x")))
  mark_open_steps("error")

  kinds <- vapply(the$stack, function(e) e$kind, character(1))
  grp <- the$stack[[which(kinds == "group")]]
  stp <- the$stack[[which(kinds == "step")]]
  expect_equal(stp$status, "error")   # the step was elevated
  expect_equal(grp$status, "running")  # the group was skipped, not elevated

  logtree_reset()  # drop the still-open step before its frame-exit defer fires
})
