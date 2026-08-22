# Message wrapping: logtree_theme(wrap = ) caps a rendered line at a column
# budget, word-wrapping the message and indenting continuation lines to the
# message column with the rails carried down. Widths are pinned to a number in
# these tests rather than measured, so the assertions are terminal-independent.

wrap_fixture <- function() {
  logtree_reset()
  pipeline <- function() {
    log_step("Pipeline")
    load_config()
  }
  load_config <- function() {
    log_step("Load config")
    log_info("Reading configuration from the deployment manifest and validating every declared parameter")
  }
  pipeline()
}

# TRUE when every line of `rendered` starts its message at exactly `cols`
# columns in. Checking the arithmetic column directly beats searching for a
# needle, which only ever appears on one of the lines.
#
# `gap` says whether a space is expected immediately before the message column
# (true whenever glyph_gap > 0). That check is what pins the column from the
# left: without it, a message starting one column early would still pass.
starts_at_column <- function(rendered, cols, gap = TRUE) {
  lines <- strsplit(rendered, "\n", fixed = TRUE)[[1L]]
  at    <- substring(lines, cols + 1L, cols + 1L)
  ok    <- nzchar(at) & at != " "
  if (gap) ok <- ok & substring(lines, cols, cols) == " "
  all(ok)
}

test_that("resolve_wrap accepts logicals and positive counts, rejects the rest", {
  expect_null(resolve_wrap(NULL))
  expect_identical(resolve_wrap(TRUE), TRUE)
  expect_identical(resolve_wrap(FALSE), FALSE)
  expect_identical(resolve_wrap(80), 80L)
  expect_identical(resolve_wrap(40L), 40L)

  expect_error(resolve_wrap(0), "positive")
  expect_error(resolve_wrap(-10), "positive")
  expect_error(resolve_wrap(c(40, 80)), "positive")
  expect_error(resolve_wrap("80"), "positive")
  expect_error(resolve_wrap(NA), "positive")
})

test_that("theme_wrap_width follows the console by default and logtree_theme(wrap=)", {
  withr::defer(logtree_theme("unicode"))

  # Wrapping is on out of the box, at the console width.
  logtree_theme("unicode")
  withr::with_options(list(cli.width = 64), expect_equal(theme_wrap_width(), 64L))

  logtree_theme(wrap = 60)
  expect_equal(theme_wrap_width(), 60L)

  logtree_theme(wrap = FALSE)
  expect_true(is.na(theme_wrap_width()))

  # A preset swap resets it to the default, as it does compact and glyph_gap.
  logtree_theme("unicode")
  withr::with_options(list(cli.width = 64), expect_equal(theme_wrap_width(), 64L))

  # A bare preset carries no wrapping at all -- that is what file sinks render
  # through, and a file has no width to wrap to.
  expect_true(is.na(theme_wrap_width(glyphs_ascii)))
})

test_that("wrap = TRUE measures the console at render time, not at set time", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = TRUE)

  withr::with_options(list(cli.width = 30), expect_equal(theme_wrap_width(), 30L))
  # Same theme, different terminal: a mid-run resize is picked up on its own.
  withr::with_options(list(cli.width = 72), expect_equal(theme_wrap_width(), 72L))
})

test_that("wrapping off leaves every line exactly as it was", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = FALSE)

  long <- strrep("word ", 40)
  expect_false(grepl("\n", format_leaf("info", long, 2L, color = FALSE), fixed = TRUE))
  expect_false(grepl("\n", format_open(
    list(depth = 2L, label = long, glyph = NULL, status = "running"),
    color = FALSE
  ), fixed = TRUE))
})

test_that("compose_line leaves cols and cont unevaluated when wrapping is off", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = FALSE)

  # Not a style preference: `cont` costs a rail_unit(), which costs a
  # cli::combine_ansi_styles() -- about a sixth of the time it takes to render
  # a line. Callers pass these as inline expressions so R's lazy arguments keep
  # the default (unwrapped) path from paying for them. Passing stop() proves it
  # stays that way: if either is ever forced, this errors.
  expect_equal(
    compose_line("|- i ", "hello", stop("cols forced"), stop("cont forced")),
    "|- i hello"
  )

  # And `cont` is still untouched when a width is set but the line fits.
  logtree_theme(wrap = 200)
  expect_equal(compose_line("|- i ", "hello", 5L, stop("cont forced")),
               "|- i hello")
})

test_that("wrap_message breaks on words and leaves short text alone", {
  expect_equal(wrap_message("short", 40), "short")
  expect_equal(wrap_message("short", NA_integer_), "short")

  out <- wrap_message("alpha beta gamma delta", 11)
  expect_true(length(out) > 1L)
  expect_true(all(cli::ansi_nchar(out, type = "width") <= 11))
  # No word is split when there is a space to break at.
  expect_equal(paste(out, collapse = " "), "alpha beta gamma delta")
})

test_that("a budget below one column degrades to no wrapping", {
  # A tree deeper than the terminal is wide: a one-column line would be
  # unusable, so the message is left to overflow instead.
  expect_equal(wrap_message("alpha beta", 0), "alpha beta")
  expect_equal(wrap_message("alpha beta", -5), "alpha beta")
})

test_that("hard_wrap splits a token that has nowhere to break", {
  token <- paste(rep("verylongsegment", 4), collapse = "/")
  out <- wrap_message(token, 20)

  expect_true(length(out) > 1L)
  expect_true(all(cli::ansi_nchar(out, type = "width") <= 20))
  # Nothing is lost or duplicated in the split.
  expect_equal(paste(out, collapse = ""), token)
})

test_that("hard_wrap never lets a wide cell straddle the column edge", {
  # Widths are walked, not characters -- two-column cells must not overflow.
  wide <- strrep("你", 12)   # U+4F60, a width-2 CJK character
  out  <- wrap_message(wide, 7)

  expect_true(all(cli::ansi_nchar(out, type = "width") <= 7))
  expect_equal(paste(out, collapse = ""), wide)
})

test_that("continuation lines land on the message column, rails intact", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 46)
  long <- "Reading configuration from the deployment manifest and validating"

  # A branch leaf: the rail continues below it, since siblings may follow.
  leaf <- format_leaf("info", long, 2L, color = FALSE)
  lines <- strsplit(leaf, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  expect_equal(lines[[1L]], "|  |- i Reading configuration from the")
  expect_match(lines[[2L]], "^\\|  \\|    ")
  # Every continuation starts its text at the same column as the first line:
  # rails (2 levels x 3) + glyph (1) + gap (1) = column 8.
  expect_true(starts_at_column(leaf, 8L))

  # A corner leaf closes its section, so nothing rails below its own column.
  corner <- format_leaf("info", long, 2L, color = FALSE, corner = TRUE)
  expect_match(strsplit(corner, "\n", fixed = TRUE)[[1L]][[2L]], "^\\|     ")
})

test_that("every line kind wraps to the same message column", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 40)
  long <- "alpha beta gamma delta epsilon zeta eta theta"

  open <- format_open(list(depth = 2L, label = long, glyph = NULL,
                           status = "running"), color = FALSE)
  leaf <- format_leaf("info", long, 2L, color = FALSE)

  # An opening line sits one level shallower than a leaf at the same depth, so
  # their columns differ by design (5 vs 8); each must be internally consistent.
  expect_true(grepl("\n", open, fixed = TRUE))
  expect_true(starts_at_column(open, 5L))

  expect_true(grepl("\n", leaf, fixed = TRUE))
  expect_true(starts_at_column(leaf, 8L))
})

test_that("close lines wrap without losing the corner", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 30,
                overrides = list(done = list(text = strrep("finished ", 5))))

  out <- format_close(list(depth = 2L, label = "Build", status = "running",
                           elapsed = 0.5), color = FALSE)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  expect_match(lines[[1L]], "^\\|  \\|- \\+ finished")
  # The corner's own column is blanked below it, not railed.
  expect_match(lines[[2L]], "^\\|     ")
})

test_that("group headers wrap under their marker, not under the name", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 38, overrides = list(group = list(glyph = "#")))

  out <- format_group_header(
    list(depth = 2L, name = "A very long suite name that will not fit"),
    color = FALSE
  )
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  expect_match(lines[[1L]], "^\\|- # ")
  # The marker column rails on the continuation: the group's members hang
  # from that column, so the wrapped name stays connected to them.
  expect_match(lines[[2L]], "^\\|  \\| \\S")
})

test_that("an open line rails its own glyph column, a leaf does not", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 34)
  long <- "alpha beta gamma delta epsilon zeta eta theta"

  # A step's glyph sits at the column its children's connectors will take, so
  # the continuation rails it -- the wrapped label reads as one node with the
  # children below it. A depth-1 root has no connector of its own, and this is
  # the only rail it has to give.
  root <- format_open(list(depth = 1L, label = long, glyph = NULL,
                           status = "running"), color = FALSE)
  expect_match(strsplit(root, "\n", fixed = TRUE)[[1L]][[2L]], "^\\| \\S")

  deep <- format_open(list(depth = 2L, label = long, glyph = NULL,
                           status = "running"), color = FALSE)
  # Its own branch connector rails (column 0) and so does its glyph (column 3).
  expect_match(strsplit(deep, "\n", fixed = TRUE)[[1L]][[2L]], "^\\|  \\| \\S")

  # Nothing ever nests under a leaf, so its glyph column stays blank.
  leaf <- format_leaf("info", long, 2L, color = FALSE)
  expect_match(strsplit(leaf, "\n", fixed = TRUE)[[1L]][[2L]], "^\\|  \\|    \\S")
})

test_that("a group header with no marker leaves its column blank", {
  # The ascii preset carries `group = list(glyph = "")`: the name starts at
  # the very column the members' connectors take, so there is no column to
  # rail without shifting the text off its own margin.
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 30)

  out <- format_group_header(
    list(depth = 1L, name = "A very long suite name that will not fit"),
    color = FALSE
  )
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  expect_match(lines[[2L]], "^\\S")
})

test_that("the emoji preset wraps on declared widths, not measured ones", {
  # ansi_nchar() cannot size an emoji cell; the column is arithmetic, which is
  # exactly why every glyph declares its own width.
  withr::defer(logtree_theme("unicode"))
  logtree_theme("emoji", wrap = 34)

  out <- format_leaf("info", "alpha beta gamma delta epsilon zeta", 2L,
                     color = FALSE)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  # Rails (2 levels x 3) + emoji glyph (2) + gap (1) = column 9.
  expect_equal(cli::ansi_nchar(sub("alpha.*$", "", lines[[1L]]), type = "width"), 9L)
  expect_equal(cli::ansi_nchar(sub("epsilon.*$", "", lines[[2L]]), type = "width"), 9L)
})

test_that("wrapping composes with glyph_gap and compact", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight", glyph_gap = 0, wrap = 24)

  out <- format_leaf("info", "alpha beta gamma delta epsilon", 2L, color = FALSE)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(length(lines) > 1L)
  expect_true(all(cli::ansi_nchar(lines, type = "width") <= 24))
  # tight: 1 column per level (2 levels) + 1-wide glyph + no gap -> 3 columns
  # of gutter. glyph_gap 0 means no space precedes the message, so the
  # left-hand check is skipped.
  expect_true(starts_at_column(out, 3L, gap = FALSE))
})

test_that("file sinks are never wrapped", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", wrap = 20)

  # File sinks render through the ascii preset, which carries no `wrap`: a file
  # has no width to wrap to (design doc section 6).
  out <- format_leaf("info", "alpha beta gamma delta epsilon zeta", 1L,
                     theme = glyphs_ascii, color = FALSE)
  expect_false(grepl("\n", out, fixed = TRUE))
})

test_that("the summary digest and run-summary line wrap too", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 34)

  f <- function() {
    log_step("Deploy")
    log_error("the registry refused the connection after three retries")
  }
  f()

  out <- capture.output(logtree_summary(rule = FALSE, gap = 0))
  # Header plus a wrapped entry.
  expect_true(length(out) > 2L)
  expect_true(all(cli::ansi_nchar(out[-1L], type = "width") <= 34))
  # Continuations indent to the digest's message column (glyph + gap = 2).
  expect_match(out[[3L]], "^  \\S")
})

test_that("a wrapped tree renders end to end (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", wrap = 46)
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot(wrap_fixture())
})
