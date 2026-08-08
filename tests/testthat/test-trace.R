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
  # No srcref, no link target either.
  expect_true(is.na(src_parts(quote(foo()))$path))
})

test_that("src_parts prints a resolvable path and carries the absolute one", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  file <- file.path(dir, "R", "job.R")
  writeLines('log_open("z")', file)
  withr::local_dir(dir)

  exprs <- parse(file, keep.source = TRUE)
  call  <- exprs[[1]]
  attr(call, "srcref") <- attr(exprs, "srcref")[[1]]
  p <- src_parts(call)

  # A basename would name a file that is not there: the printed form has to be
  # relative to the working directory for anything to resolve it.
  expect_equal(p$file, file.path("R", "job.R"))
  expect_equal(p$path, normalizePath(file, winslash = "/"))
  expect_equal(p$line, 1L)
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

test_that("resolve_trace_show normalises to FALSE or a set of statuses", {
  th <- glyphs_ascii
  th$trace$show <- FALSE
  expect_false(resolve_trace_show(th))
  # The two shorthands are resolved away here, which is what lets every
  # downstream decision be a single membership test.
  th$trace$show <- TRUE
  expect_equal(resolve_trace_show(th), trace_statuses)
  th$trace$show <- "problems"
  expect_equal(resolve_trace_show(th), c("warning", "error", "interrupted"))
  # TRUE has to stay a strict superset of "problems".
  expect_true(all(c("warning", "error", "interrupted") %in% trace_statuses))

  th$trace$show <- c("error", "interrupted")
  expect_equal(resolve_trace_show(th), c("error", "interrupted"))
  # Unknown tokens are dropped rather than passed through to the membership
  # test, where they would silently match nothing.
  th$trace$show <- c("error", "oops")
  expect_equal(resolve_trace_show(th), "error")

  # Anything unrecognised reads as off, matching how the elapsed slot's fields
  # are checked defensively at use rather than validated when set.
  th$trace$show <- "problem"
  expect_false(resolve_trace_show(th))
  th$trace$show <- character(0)
  expect_false(resolve_trace_show(th))
  th$trace$show <- NA_character_
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

# --- Per-part styling and hyperlinks ---------------------------------------

# cli decides both of these from the terminal it finds itself in, and under
# testthat it finds none. Force them on so the escapes are actually emitted.
local_ansi <- function(envir = parent.frame()) {
  withr::local_options(cli.num_colors = 256L, cli.hyperlink = TRUE,
                       .local_envir = envir)
}

test_that("the location is styled whole and the function name alone", {
  local_ansi()
  styles <- list(base = "dim", location = "blue", fn = "cyan")
  out <- expand_trace_text("{file}:{line} {fn}()", test_trace(), styles = styles)

  # One style over the location, separator included -- not two styled halves
  # with a bare ":" between them.
  expect_match(out, cli::combine_ansi_styles("blue")("pipeline.R:12"),
               fixed = TRUE)
  # The function name is styled on its own, so the "()" after it is left to the
  # caller's `base` pass.
  expect_match(out, paste0(cli::combine_ansi_styles("cyan")("load_data"), "()"),
               fixed = TRUE)
  expect_equal(cli::ansi_strip(out), "pipeline.R:12 load_data()")
})

test_that("a character color still styles the whole column", {
  local_ansi()
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE, color = "dim")

  # The pre-list form of the slot: one style, applied once, no per-part
  # escapes inside it.
  out <- render_trace_text(test_trace())
  expect_equal(out, cli::combine_ansi_styles("dim")("pipeline.R:12 load_data()"))
})

test_that("the location links to the file and the width is unchanged", {
  local_ansi()
  tr  <- test_trace(path = "/tmp/pipeline.R")
  out <- expand_trace_text("{file}:{line} {fn}()", tr, link = TRUE)

  expect_match(out, "file:///tmp/pipeline.R", fixed = TRUE)
  # One link over "pipeline.R:12", not one per half, and none on the function
  # name -- a function is not a place.
  expect_equal(lengths(gregexpr("file:///tmp/pipeline.R", out, fixed = TRUE)),
               1L)
  expect_match(cli::ansi_strip(out, link = FALSE), "pipeline\\.R:12\033\\]8;;")
  expect_equal(cli::ansi_strip(out), "pipeline.R:12 load_data()")
  # The escape has no printable width, so compose_line()'s wrapping arithmetic
  # is unaffected by it.
  expect_equal(cli::ansi_nchar(out, type = "width"),
               nchar("pipeline.R:12 load_data()"))
})

test_that("no path means no link, and a plain sink never links", {
  local_ansi()
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  # keep.source = FALSE, an installed package, a deleted file: text only.
  expect_equal(expand_trace_text("{file}:{line}", test_trace(), link = TRUE),
               "pipeline.R:12")
  # color = FALSE is the file-sink path: neither style nor link may reach it.
  expect_equal(render_trace_text(test_trace(path = "/tmp/pipeline.R"),
                                 color = FALSE),
               "pipeline.R:12 load_data()")
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
               "> Pipeline  pipeline.R:12 load_data()")
  expect_equal(
    format_leaf("info", "reading", 1L, color = FALSE, trace = test_trace()),
    "|- i reading  pipeline.R:12 load_data()"
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
               "|- ! coerced  pipeline.R:12 load_data()")
  expect_equal(format_leaf("error", "bad row", 1L, color = FALSE, trace = tr),
               "|- x bad row  pipeline.R:12 load_data()")

  # An open line stays clean under "problems".
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "running", elapsed = 0.5, trace = tr)
  expect_equal(format_open(entry, color = FALSE), "> Pipeline")

  # An interrupted close is the one close line that does carry it: there is no
  # accompanying leaf to hang the location on.
  entry$status <- "interrupted"
  expect_match(format_close(entry, color = FALSE), "pipeline\\.R:12 load_data\\(\\)$")

  entry$status <- "warning"
  expect_equal(format_close(entry, color = FALSE), "|- ! Done  0.50s")
})

test_that("a status vector traces exactly the statuses it names", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("error")

  tr <- test_trace()
  # The whole point of the vector form: errors without their warnings.
  expect_equal(format_leaf("error", "bad row", 1L, color = FALSE, trace = tr),
               "|- x bad row  pipeline.R:12 load_data()")
  expect_equal(format_leaf("warning", "coerced", 1L, color = FALSE, trace = tr),
               "|- ! coerced")

  # "interrupted" is not implied by "error": an unwound step is its own status.
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "interrupted", elapsed = 0.5, trace = tr)
  expect_no_match(format_close(entry, color = FALSE), "pipeline.R", fixed = TRUE)

  local_trace(c("error", "interrupted"))
  expect_match(format_close(entry, color = FALSE),
               "pipeline\\.R:12 load_data\\(\\)$")
})

test_that("statuses map onto the line kinds that can report them", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  tr    <- test_trace()
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "running", elapsed = 0.5, trace = tr)

  # "running" is what an open line reports, so it is the token that turns open
  # lines on -- and it says nothing about leaves.
  local_trace("running")
  expect_equal(format_open(entry, color = FALSE),
               "> Pipeline  pipeline.R:12 load_data()")
  expect_equal(format_leaf("info", "reading", 1L, color = FALSE, trace = tr),
               "|- i reading")

  # A clean close stays clean even when its status is named: its site is its
  # own open line's, two rows up.
  local_trace(c("running", "success"))
  entry$status <- "success"
  expect_equal(format_close(entry, color = FALSE), "|- + Done  0.50s")
  expect_equal(format_leaf("success", "ok", 1L, color = FALSE, trace = tr),
               "|- + ok  pipeline.R:12 load_data()")
})

test_that("a set naming nothing real is off, like any unrecognised show", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("errors")  # plural: not the status vocabulary

  expect_false(trace_enabled())
  expect_equal(format_leaf("error", "bad row", 1L, color = FALSE,
                           trace = test_trace()),
               "|- x bad row")
})

test_that("show = TRUE is a superset of \"problems\"", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace(TRUE)

  # Turning the column up must never take away a line the quieter setting shows.
  entry <- list(depth = 1L, label = "Pipeline", glyph = NULL,
                status = "interrupted", elapsed = 0.5, trace = test_trace())
  expect_match(format_close(entry, color = FALSE), "pipeline\\.R:12 load_data\\(\\)$")
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

  expect_true(any(grepl("reading  demo.R:7 f()", readLines(path), fixed = TRUE)))
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
  expect_true(any(grepl("reading  demo.R:7 f()", readLines(path), fixed = TRUE)))
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

  expect_true(any(grepl("coerced 3 rows  pipeline.R:20 parse_rows()", out,
                        fixed = TRUE)))
})

test_that("the digest applies the same status filter as the tree", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()
  local_trace("error")
  freeze_srcref("pipeline.R", 20L)

  job <- function() {
    log_step("Job")
    log_warn("coerced 3 rows")
    log_error("no numeric columns")
  }
  invisible(capture.output(job()))
  out <- capture.output(logtree_summary())

  # show = "error" means errors only wherever you read it, digest included --
  # the point of naming statuses rather than taking a bundle.
  expect_true(any(grepl("no numeric columns  pipeline.R:20 job()", out,
                        fixed = TRUE)))
  warn_line <- grep("coerced 3 rows", out, fixed = TRUE, value = TRUE)
  expect_length(warn_line, 1L)
  expect_false(any(grepl("pipeline.R", warn_line, fixed = TRUE)))
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
