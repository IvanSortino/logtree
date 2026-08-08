# --- The default: nothing changes -------------------------------------------

test_that("trace is off in every preset, and off costs no capture", {
  # test-preset-minimal.R pins the wider names() contract across presets; this
  # pins the values, because a preset that shipped show = TRUE would turn the
  # feature on for everyone.
  for (p in list(glyphs_unicode, glyphs_ascii, glyphs_emoji,
                 glyphs_minimal, glyphs_ci)) {
    expect_false(p$trace$show)
    expect_type(p$trace$format, "character")
  }

  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  expect_false(trace_enabled())

  # With the slot off nothing is captured, so the entry carries no trace at all
  # -- not merely an unrendered one.
  f <- function() log_open("Step")
  f()
  expect_null(the$stack[[1]]$trace)
})

test_that("trace off renders byte-identical output", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "running", elapsed = 0.5, trace = test_trace())
  # A trace is present on the entry but the slot is off: not one character of it
  # may reach the line.
  expect_equal(format_open(entry, color = FALSE), "> Pipeline")
  expect_equal(format_close(entry, color = FALSE), "|- + Done  0.50s")
  expect_equal(
    format_leaf("info", "reading", 1L, color = FALSE, trace = test_trace()),
    "|- i reading"
  )
})

# --- src_parts() / capture --------------------------------------------------

test_that("src_parts splits a call site, and reports NA without a srcref", {
  # quote() carries no srcref.
  p <- src_parts(quote(foo()))
  expect_true(is.na(p$file))
  expect_true(is.na(p$line))

  # R attaches a call's srcref during evaluation; a statically parsed element
  # does not, so attach it the way R would (see test-srckey.R).
  exprs <- parse(text = 'log_open("z")', keep.source = TRUE)
  call  <- exprs[[1]]
  attr(call, "srcref") <- attr(exprs, "srcref")[[1]]
  p <- src_parts(call)
  expect_equal(p$line, 1L)
  expect_type(p$file, "character")
})

test_that("src_location still returns the joined form it always did", {
  expect_true(is.na(src_location(quote(foo()))))

  exprs <- parse(text = 'log_open("z")', keep.source = TRUE)
  call  <- exprs[[1]]
  attr(call, "srcref") <- attr(exprs, "srcref")[[1]]
  expect_match(src_location(call), ":1$")
})

test_that("call_fn_name handles plain calls, odd calls, and NULL", {
  expect_equal(call_fn_name(quote(load_data())), "load_data")
  expect_true(is.na(call_fn_name(NULL)))
  # Not a simple f(...) -- a legitimate outcome, not an error.
  expect_true(is.na(call_fn_name(quote((function() 1)()))))
})

test_that("resolve_trace_show normalises to FALSE, TRUE or \"problems\"", {
  th <- glyphs_ascii
  th$trace$show <- FALSE
  expect_false(resolve_trace_show(th))
  th$trace$show <- TRUE
  expect_true(resolve_trace_show(th))
  th$trace$show <- "problems"
  expect_equal(resolve_trace_show(th), "problems")
  # Anything unrecognised reads as off, matching how the elapsed slot's fields
  # are checked defensively at use rather than validated when set.
  th$trace$show <- "problem"
  expect_false(resolve_trace_show(th))
  th$trace$show <- 3
  expect_false(resolve_trace_show(th))
})

# --- Frame offsets: the constants that would silently misattribute ----------

test_that("log_step and log_open trace to the enclosing function", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  load_data <- function() log_open("Load data")
  load_data()
  expect_equal(the$stack[[1]]$trace$fn, "load_data")

  logtree_reset()
  outer <- function() {
    log_step("Step")
    expect_equal(the$stack[[1]]$trace$fn, "outer")
  }
  outer()
})

test_that("a leaf traces to its own enclosing function, not to emit_leaf", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)
  local_reset_sinks()

  seen <- list()
  the$sinks <- c(the$sinks, list(function(event) {
    if (identical(event$kind, "leaf")) seen[[length(seen) + 1L]] <<- event
  }))

  parse_rows <- function() {
    log_info("1200 rows")
    log_warn("coerced 3 rows")
  }
  invisible(capture.output(parse_rows()))

  expect_length(seen, 2L)
  # This is the assertion that pins emit_leaf()'s up = 2: a wrapper added at a
  # different depth would report "emit_leaf" or "log_info" here instead.
  expect_equal(seen[[1]]$trace$fn, "parse_rows")
  expect_equal(seen[[2]]$trace$fn, "parse_rows")
})

test_that("a verbosity-suppressed leaf captures nothing", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)
  local_reset_verbosity()
  local_reset_sinks()
  logtree_threshold("info")   # debug is below the gate

  seen <- 0L
  the$sinks <- c(the$sinks, list(function(event) seen <<- seen + 1L))

  f <- function() log_debug("cache miss")
  invisible(capture.output(f()))
  expect_equal(seen, 0L)
})

# --- Template expansion ----------------------------------------------------

test_that("the default template expands both halves", {
  expect_equal(
    expand_trace_text("{fn}() {file}:{line}", test_trace()),
    "load_data() pipeline.R:12"
  )
})

test_that("a run whose placeholders are all unavailable is dropped whole", {
  no_loc <- list(fn = "load_data", file = NA_character_, line = NA_integer_)
  # This is the keep.source = FALSE case: degrade to the function name rather
  # than print "NA:NA" or leave a dangling ":".
  expect_equal(expand_trace_text("{fn}() {file}:{line}", no_loc), "load_data()")
  # A location-only format collapses to nothing, so no column is printed.
  expect_equal(expand_trace_text("{file}:{line}", no_loc), "")

  # And the mirror case: no function name (top level), location intact.
  no_fn <- list(fn = NA_character_, file = "pipeline.R", line = 5L)
  expect_equal(expand_trace_text("{fn}() {file}:{line}", no_fn), "pipeline.R:5")
})

test_that("single-placeholder formats work", {
  expect_equal(expand_trace_text("{fn}()", test_trace()), "load_data()")
  expect_equal(expand_trace_text("{file}:{line}", test_trace()), "pipeline.R:12")
  expect_equal(expand_trace_text("{line}", test_trace()), "12")
})

test_that("a substituted value is never rescanned as a template", {
  # A function literally named "{line}" must be inserted as data. This is the
  # regression guard for commit 3b5803d, in the new expander.
  tr <- list(fn = "{line}", file = "pipeline.R", line = 99L)
  expect_equal(expand_trace_text("{fn}()", tr), "{line}()")
  expect_equal(expand_trace_text("{fn}() {line}", tr), "{line}() 99")
})

test_that("a template with no placeholders passes through", {
  expect_equal(expand_trace_text("here", test_trace()), "here")
  expect_equal(expand_trace_text("", test_trace()), "")
})

# --- The show policy -------------------------------------------------------

test_that("show = TRUE traces open lines and leaves but not clean closes", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "running", elapsed = 0.5, trace = test_trace())
  expect_equal(format_open(entry, color = FALSE),
               "> Pipeline  load_data() pipeline.R:12")
  expect_equal(
    format_leaf("info", "reading", 1L, color = FALSE, trace = test_trace()),
    "|- i reading  load_data() pipeline.R:12"
  )
  # A clean close carries none: its site is its own open line's.
  expect_equal(format_close(entry, color = FALSE), "|- + Done  0.50s")
})

test_that("show = \"problems\" traces only what went wrong", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("problems")

  tr <- test_trace()
  # Ordinary leaves stay clean, whatever their level.
  expect_equal(format_leaf("info", "quiet", 1L, color = FALSE, trace = tr),
               "|- i quiet")
  expect_equal(format_leaf("success", "quiet", 1L, color = FALSE, trace = tr),
               "|- + quiet")
  expect_equal(format_leaf("debug", "quiet", 1L, color = FALSE, trace = tr),
               "|- d quiet")

  expect_equal(format_leaf("warning", "coerced", 1L, color = FALSE, trace = tr),
               "|- ! coerced  load_data() pipeline.R:12")
  expect_equal(format_leaf("error", "bad row", 1L, color = FALSE, trace = tr),
               "|- x bad row  load_data() pipeline.R:12")

  # An open line stays clean under "problems".
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "running", elapsed = 0.5, trace = tr)
  expect_equal(format_open(entry, color = FALSE), "> Pipeline")

  # An interrupted close is the one close line that does carry it: there is no
  # accompanying leaf to hang the location on.
  entry$status <- "interrupted"
  expect_match(format_close(entry, color = FALSE), "load_data\\(\\) pipeline\\.R:12$")

  entry$status <- "warning"
  expect_equal(format_close(entry, color = FALSE), "|- ! Done  0.50s")
})

test_that("show = TRUE is a superset of \"problems\"", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  # Turning the column up must never take away a line the quieter setting shows.
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "interrupted", elapsed = 0.5, trace = test_trace())
  expect_match(format_close(entry, color = FALSE), "load_data\\(\\) pipeline\\.R:12$")
})

test_that("a group header never carries a trace", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  entry <- list(depth = 1L, kind = "group", name = "Item 1", status = "running")
  expect_equal(format_group_header(entry, color = FALSE), "< Item 1 >")
})

# --- Wrapping --------------------------------------------------------------

test_that("an inline trace counts toward the wrap width", {
  logtree_reset()
  withr::defer(logtree_reset())
  logtree_theme("ascii", wrap = 40)
  withr::defer(logtree_theme("unicode"))
  local_trace(TRUE)

  msg <- "reading records from the manifest"
  # Fits on one line without the trace...
  no_trace <- format_leaf("info", msg, 1L, color = FALSE)
  expect_false(grepl("\n", no_trace))
  # ...and wraps once the trace is appended, because the trace goes into the
  # message rather than into a column of its own.
  with_tr <- format_leaf("info", msg, 1L, color = FALSE, trace = test_trace())
  expect_true(grepl("\n", with_tr))
})

# --- Theme plumbing --------------------------------------------------------

test_that("the trace slot goes through logtree_theme() like any other", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  logtree_theme(list(trace = list(show = TRUE, format = "{fn}()")))
  expect_true(the$theme$trace$show)
  expect_equal(the$theme$trace$format, "{fn}()")

  # Naming a preset clears the override, like every other slot.
  logtree_theme("ascii")
  expect_false(the$theme$trace$show)
})

test_that("trace declares no width, so it is not a status slot", {
  expect_false("trace" %in% glyph_keys)
  expect_null(glyphs_unicode$trace$width)
})

# --- Sinks -----------------------------------------------------------------

test_that("a text sink follows the console by default", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  local_trace(TRUE)
  freeze_srcref("demo.R", 7L)

  path <- tempfile(fileext = ".log")
  logtree_sink_file(path, format = "text")

  f <- function() log_info("reading")
  invisible(capture.output(f()))

  expect_true(any(grepl("reading  f() demo.R:7", readLines(path), fixed = TRUE)))
})

test_that("a text sink can carry trace with the console column off", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()
  freeze_srcref("demo.R", 7L)

  path <- tempfile(fileext = ".log")
  logtree_sink_file(path, format = "text", trace = TRUE)
  # The sink alone must switch capture on, or it would render a column that was
  # never populated.
  expect_true(trace_enabled())

  f <- function() log_info("reading")
  out <- capture.output(f())

  # File has it, console does not.
  expect_true(any(grepl("reading  f() demo.R:7", readLines(path), fixed = TRUE)))
  expect_false(any(grepl("demo.R", out, fixed = TRUE)))
})

test_that("the JSON sink always carries fn/file/line, null when absent", {
  skip_if_not_installed("jsonlite")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_sinks()

  # Trace off: the keys are still emitted, as null. Assert on the raw line
  # rather than on names() of the parsed object -- whether a null-valued key
  # survives parsing is jsonlite's business, not this package's contract.
  off <- tempfile(fileext = ".ndjson")
  logtree_sink_file(off, format = "json")
  f <- function() log_info("reading")
  invisible(capture.output(f()))
  raw <- readLines(off)[[1]]
  expect_match(raw, '"fn":null', fixed = TRUE)
  expect_match(raw, '"file":null', fixed = TRUE)
  expect_match(raw, '"line":null', fixed = TRUE)
  expect_silent(jsonlite::fromJSON(raw))

  # Trace on: populated.
  logtree_reset()
  the$sinks <- list(console_sink)
  local_trace(TRUE)
  freeze_srcref("demo.R", 7L)
  on <- tempfile(fileext = ".ndjson")
  logtree_sink_file(on, format = "json")
  g <- function() log_info("reading")
  invisible(capture.output(g()))
  rec <- jsonlite::fromJSON(readLines(on)[[1]])
  expect_equal(rec$fn, "g")
  expect_equal(rec$file, "demo.R")
  expect_equal(rec$line, 7L)
})

# --- Digest ----------------------------------------------------------------

test_that("digest lines carry the call site", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("problems")
  freeze_srcref("pipeline.R", 20L)

  parse_rows <- function() {
    log_step("Parse rows")
    log_warn("coerced 3 rows")
  }
  invisible(capture.output(parse_rows()))
  out <- capture.output(logtree_summary())

  expect_true(any(grepl("coerced 3 rows  parse_rows() pipeline.R:20", out,
                        fixed = TRUE)))
})

test_that("digest entries expose the trace in the returned records", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("problems")
  freeze_srcref("pipeline.R", 20L)

  f <- function() {
    log_step("Step")
    log_error("boom")
  }
  invisible(capture.output(f()))
  invisible(capture.output(res <- logtree_summary()))
  expect_equal(res[[1]]$trace$fn, "f")
  expect_equal(res[[1]]$trace$file, "pipeline.R")
})

# --- The two call sites that would otherwise lie ---------------------------

test_that("with_logging traces a thrown error to the throwing call", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("problems")

  boom <- function() stop("constraint violation")
  runner <- function() {
    log_step("Apply migration")
    boom()
  }
  out <- capture.output(
    try(with_logging(runner(), summary = FALSE), silent = TRUE)
  )

  # The leaf must name boom(), the call that threw -- never the handler inside
  # with_logging() that logged it.
  expect_true(any(grepl("constraint violation  boom()", out, fixed = TRUE)))
  expect_false(any(grepl("log_error", out, fixed = TRUE)))
})

test_that("a logger-routed leaf traces to the logger call, not the layout", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  ns <- "logtree_trace_test"
  withr::defer({
    logger::log_layout(logger::layout_simple, namespace = ns)
    logger::log_appender(logger::appender_console, namespace = ns)
    logger::log_threshold(logger::INFO, namespace = ns)
  })
  logtree_logger(namespace = ns)

  caller <- function() {
    log_step("Step")
    logger::log_info("hello", namespace = ns)
  }
  out <- capture.output(invisible(caller()))

  expect_true(any(grepl("hello", out, fixed = TRUE)))
  # The bug this guards: without .topcall the trace names layout_logtree.
  expect_false(any(grepl("layout_logtree", out, fixed = TRUE)))
})

test_that("logger severities still map onto the right leaf glyphs", {
  skip_if_not_installed("logger")
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_reset_verbosity()
  logtree_threshold("debug")

  # layout_logtree() now maps to a status rather than to a leaf function; this
  # re-pins the mapping, including the elevation that log_warn()/log_error()
  # used to perform.
  f <- function() {
    log_open("Step")
    layout_logtree(logger::WARN, "warn via logger")
  }
  out <- capture.output(invisible(f()))
  expect_true(any(grepl("^\\|- ! warn via logger$", out)))
  expect_equal(the$stack[[1]]$status, "warning")
})
