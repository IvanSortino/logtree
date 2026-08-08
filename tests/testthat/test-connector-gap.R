# connector_gap: the spaces between a leaf or close line's OWN connector and
# its status glyph, independent of col_gap (which spaces every ancestor rail
# column). It defaults to col_gap, so a preset or a compact density that sets
# only col_gap renders exactly as before; it diverges only once set explicitly.
# ascii is used throughout since its output is theme-stable.

gap_entry <- function(d) {
  list(depth = d, label = "Build", glyph = NULL, status = "running", elapsed = 0.5)
}

test_that("resolve_connector_gap accepts non-negative scalars, rejects the rest", {
  expect_null(resolve_connector_gap(NULL))
  expect_identical(resolve_connector_gap(0), 0L)
  expect_identical(resolve_connector_gap(3L), 3L)

  expect_error(resolve_connector_gap(-1), "non-negative")
  expect_error(resolve_connector_gap(c(1, 2)), "non-negative")
  expect_error(resolve_connector_gap("1"), "non-negative")
  expect_error(resolve_connector_gap(NA), "non-negative")
})

test_that("connector_gap tracks col_gap until it is set explicitly", {
  withr::defer(logtree_theme("unicode"))

  # This fallback is what keeps every preset and every compact density
  # rendering byte-for-byte as they did before the setting existed.
  logtree_theme("ascii")
  expect_equal(theme_connector_gap(), theme_col_gap())
  expect_equal(theme_connector_gap(), 1L)

  logtree_theme("ascii", compact = "medium")
  expect_equal(theme_connector_gap(), 0L)

  logtree_theme("ascii", compact = "tight")
  expect_equal(theme_connector_gap(), 0L)

  # Set explicitly, it diverges from col_gap rather than following it.
  logtree_theme("ascii", compact = "tight", connector_gap = 2)
  expect_equal(theme_col_gap(), 0L)
  expect_equal(theme_connector_gap(), 2L)

  # A preset swap clears it, as it does compact / glyph_gap / wrap.
  logtree_theme("ascii")
  expect_equal(theme_connector_gap(), 1L)
})

test_that("connector_gap spaces leaf and close glyphs but never a step open", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight", connector_gap = 1)

  # The point of the setting: rails stay flush (col_gap 0) while a leaf's own
  # connector is spaced off its glyph.
  # ascii `tight` slims the branch/corner connectors to one character, so the
  # only space on these lines is connector_gap's.
  expect_equal(format_leaf("info", "msg", 2L, color = FALSE), "|| i msg")
  expect_equal(format_close(gap_entry(2L), color = FALSE), "|| + Done  0.50s")
  # A step's opening line renders flush at any density -- it is a rail column,
  # not the glyph's own approach. (The space after ">" is glyph_gap, which is
  # a separate setting and still 1 here.)
  expect_equal(format_open(gap_entry(2L), color = FALSE), "|> Build")
  # Group headers are open lines too.
  expect_equal(
    format_group_header(list(depth = 2L, name = "Suite 1"), color = FALSE),
    "|< Suite 1 >"
  )
})

test_that("connector_gap widens only the line's own column, not the rails", {
  withr::defer(logtree_theme("unicode"))

  # Deeper lines must still advance one tree column per level: the extra gap
  # belongs to the connector's own approach, so it must not compound with
  # depth or the tree would fan out to the right.
  logtree_theme("ascii", compact = "tight", connector_gap = 3)
  widths <- vapply(1:4, function(d) {
    nchar(sub("i msg$", "", format_leaf("info", "msg", d, color = FALSE)))
  }, integer(1))
  expect_equal(diff(widths), rep(1L, 3L))
})

test_that("a wrapped line lands on the message column at any connector_gap", {
  withr::defer(logtree_theme("unicode"))
  long <- "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"

  for (gap in c(0L, 1L, 3L)) {
    logtree_theme("ascii", compact = "tight", connector_gap = gap, wrap = 40)
    # ascii tight: 1 column per level, corner/branch 1 char, glyph gutter 2.
    # A leaf at depth d starts its message at (d - 1) + (1 + gap) + 2.
    for (d in 2:4) {
      expected <- (d - 1L) + (1L + gap) + 2L
      for (corner in c(FALSE, TRUE)) {
        out   <- format_leaf("info", long, d, color = FALSE, corner = corner)
        lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
        expect_true(length(lines) > 1L)
        # Every line's message begins at the same computed column, and the
        # column before it is blank.
        at <- substring(lines, expected + 1L, expected + 1L)
        expect_true(all(nzchar(at) & at != " "))
        expect_equal(unique(substring(lines, expected, expected)), " ")
      }
    }
  }
})

test_that("file sinks keep their built-in spacing whatever the console sets", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("unicode", compact = "tight", connector_gap = 4)

  # File sinks render through the ascii preset, which carries no connector_gap
  # and so falls back to its own col_gap (design doc section 6).
  expect_equal(
    format_leaf("info", "hello", 1L, theme = glyphs_ascii, color = FALSE),
    "|- i hello"
  )
})

test_that("connector_gap composes with glyph_gap without disturbing it", {
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight", connector_gap = 2, glyph_gap = 0)

  # connector_gap sits before the glyph, glyph_gap after it.
  expect_equal(format_leaf("info", "msg", 2L, color = FALSE), "||  imsg")
})

test_that("connector_gap renders a whole tree (ascii)", {
  withr::defer(logtree_reset())
  withr::defer(logtree_theme("unicode"))
  logtree_theme("ascii", compact = "tight", connector_gap = 1)
  freeze_clock(c(0, 0, 0.03, 0.15))

  expect_snapshot({
    logtree_reset()
    pipeline <- function() {
      log_step("Pipeline")
      load_config()
    }
    load_config <- function() {
      log_step("Load config")
      log_info("Reading config.yml")
    }
    pipeline()
  })
})
