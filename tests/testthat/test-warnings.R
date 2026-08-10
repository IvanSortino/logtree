test_that("warnings = TRUE routes warning() into the tree as a leaf", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      warning("3 rows coerced to NA")
    }, summary = FALSE, warnings = TRUE)
  }
  out <- capture.output(invisible(f()))

  expect_true(any(grepl("^\\|- ! 3 rows coerced to NA$", out)))
})

test_that("warnings = TRUE routes message() as an info leaf", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      message("using cached manifest")
    }, summary = FALSE, warnings = TRUE)
  }
  out <- capture.output(invisible(f()))

  # message() conditions carry a trailing newline; it must not become a blank
  # row through the middle of the tree.
  expect_true(any(grepl("^\\|- i using cached manifest$", out)))
  expect_false(any(!nzchar(out)))
})

test_that("a routed warning elevates the enclosing step, like log_warn()", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      warning("coerced")
    }, summary = FALSE, warnings = TRUE)
  }
  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- ! Done")
})

test_that("a routed message does not elevate the step", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      message("just so you know")
    }, summary = FALSE, warnings = TRUE)
  }
  out <- capture.output(invisible(f()))
  expect_match(out[length(out)], "^\\|- \\+ Done")
})

test_that("routed conditions are muffled", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      warning("coerced")
      message("noted")
    }, summary = FALSE, warnings = TRUE)
  }
  # Neither reaches the caller: no warning condition escapes, and nothing is
  # written to stderr. The tree is the single record.
  expect_silent(out <- capture.output(invisible(f())))
  expect_true(any(grepl("coerced", out)))
})

test_that("warnings = FALSE (the default) leaves conditions completely alone", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      warning("untouched")
    }, summary = FALSE)
  }
  out <- capture.output(expect_warning(invisible(f()), "untouched"))
  expect_false(any(grepl("untouched", out)))
  # The step closes clean: an unrouted warning does not elevate anything.
  expect_match(out[length(out)], "^\\|- \\+ Done")
})

test_that("a subset routes only what it names", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Load data")
      warning("routed")
      message("left alone")
    }, summary = FALSE, warnings = "warning")
  }
  out <- capture.output(expect_message(invisible(f()), "left alone"))
  expect_true(any(grepl("routed", out)))
  expect_false(any(grepl("left alone", out)))

  logtree_reset()
  g <- function() {
    with_logging({
      log_step("Load data")
      warning("left alone")
      message("routed")
    }, summary = FALSE, warnings = "message")
  }
  out <- capture.output(expect_warning(invisible(g()), "left alone"))
  expect_true(any(grepl("routed", out)))
})

test_that("with_logging validates `warnings`", {
  expect_error(with_logging(NULL, warnings = "wornings"),
               'subset of c\\("warning", "message"\\)')
  expect_error(with_logging(NULL, warnings = 1L), "must be TRUE, FALSE")
  expect_error(with_logging(NULL, warnings = NA), "must be TRUE, FALSE")
})

test_that("routing does not disturb the error handler", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Fetching")
      log_step("Parsing")
      warning("coerced")
      stop("model timeout after 30s")
    }, summary = FALSE, warnings = TRUE)
  }

  out <- capture.output(expect_error(f(), "model timeout after 30s"))
  # The warning became a leaf, the error still marks every open step and is
  # still rethrown.
  expect_true(any(grepl("! coerced", out)))
  expect_true(any(grepl("x model timeout after 30s", out)))
  expect_length(grep("x Done", out), 2)
  expect_length(the$stack, 0)
})

test_that("a routed condition carries the call site that raised it", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)
  freeze_srcref("demo.R", 7L)

  raiser <- function() warning("from here")
  f <- function() {
    with_logging({
      log_step("Step")
      raiser()
    }, summary = FALSE, warnings = TRUE)
  }
  out <- capture.output(invisible(f()))

  # Not "route_condition" or "with_logging": a handler logs from its own frame,
  # so the site has to come from conditionCall().
  expect_true(any(grepl("from here  demo.R:7 raiser()", out, fixed = TRUE)))
})

test_that("a sink that warns while routing does not recurse", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  # This is the shape that would loop: a leaf reaches the sinks, the sink
  # throws, emit() warns about it -- and with routing on, that warning arrives
  # back at the very handler that produced the leaf.
  logtree_sink(function(event) stop("sink is broken"))

  f <- function() {
    with_logging({
      log_step("Step")
      warning("kick it off")
    }, summary = FALSE, warnings = TRUE)
  }

  # It terminates, and the sink complaint is itself routed into the tree --
  # once, since the sink is marked before the warning goes out.
  expect_silent(out <- capture.output(invisible(f())))
  expect_length(grep("threw and was skipped", out), 1L)
  expect_true(any(grepl("kick it off", out)))
  expect_length(the$stack, 0)
  expect_false(isTRUE(the$routing))
})

test_that("a condition with no muffle restart is routed without erroring", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # signalCondition() establishes no muffleWarning restart, so invoking one
  # blindly would error where the condition itself was harmless.
  cnd <- structure(
    class = c("custom_warning", "warning", "condition"),
    list(message = "signalled, not warned", call = NULL)
  )
  f <- function() {
    with_logging({
      log_step("Step")
      withRestarts(signalCondition(cnd), muffleThis = function() NULL)
    }, summary = FALSE, warnings = TRUE)
  }

  # Routed into the tree, and -- there being no restart to muffle it with --
  # left to carry on to whatever else is listening, rather than erroring. The
  # outer handler here is what proves the second half: it still gets the
  # condition, and muffles it through the restart the raiser did establish.
  out <- withCallingHandlers(
    capture.output(invisible(f())),
    custom_warning = function(w) invokeRestart("muffleThis")
  )
  expect_true(any(grepl("signalled, not warned", out)))
})

test_that("the routing flag is left clean afterwards", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  f <- function() {
    with_logging({
      log_step("Step")
      warning("one")
    }, summary = FALSE, warnings = TRUE)
  }
  invisible(capture.output(f()))
  expect_false(isTRUE(the$routing))

  # And after an error unwinds through the handler, too.
  g <- function() {
    with_logging({
      log_step("Step")
      warning("two")
      stop("boom")
    }, summary = FALSE, warnings = TRUE)
  }
  invisible(capture.output(try(g(), silent = TRUE)))
  expect_false(isTRUE(the$routing))
})

test_that("global mode routes conditions only while steps are open", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # global = TRUE must be called from a clean top level, which a test_that()
  # block is not; exercise the guard through route_condition() directly, the
  # way test-with-logging.R exercises global_error_action().
  cnd <- simpleWarning("from unrelated code", call = NULL)

  # Stack empty: left alone entirely.
  expect_equal(capture.output(route_warning(cnd, guard = TRUE)), character(0))
  expect_length(the$summary, 0)

  # Steps open: routed as a leaf.
  log_open("Step")
  out <- capture.output(route_warning(cnd, guard = TRUE))
  expect_true(any(grepl("! from unrelated code", out)))
  log_close()
})

test_that("resolve_warnings normalises every accepted form", {
  expect_equal(resolve_warnings(FALSE), character(0))
  expect_equal(resolve_warnings(TRUE), c("warning", "message"))
  expect_equal(resolve_warnings("warning"), "warning")
  expect_equal(resolve_warnings(c("message", "message")), "message")
  expect_equal(resolve_warnings(c("warning", "message")), c("warning", "message"))
})
