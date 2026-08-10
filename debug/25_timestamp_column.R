# The timestamp column: the `timestamp` theme slot puts wall-clock time in
# front of every line.
#
#   format -- a strftime format, NULL (the default in every preset) for off
#   color  -- cli styles for the column
#
# A live tree already says how *long* each step took. What it never said is
# *when* any of it happened, so a log read after the fact could not be lined up
# against anything else -- a monitoring graph, another service's log, a support
# ticket that says "around half past two".
#
# It is an ordinary override slot, so it goes through logtree_theme()'s
# `overrides` like any glyph slot -- no new argument.
#
# The one thing worth understanding before reading the output: the column is
# padded to a *fixed* width, measured from a rendered sample rather than from
# the format string. A format whose width varies with the value (a bare
# day-of-month, say) would otherwise push the whole tree left and right from one
# line to the next. Section D shows that on purpose.
#
#   Rscript -e 'devtools::load_all(); source("debug/25_timestamp_column.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = TRUE)
}

# One shared fixture: nested, grouped, and with a warning, so every line kind
# gets a turn at carrying the column.
tree <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  batch("A")
  batch("B")
}
batch <- function(name) {
  log_step(paste("Article", name), group = c(Batch = "b1"))
  log_info("fetched")
  if (identical(name, "B")) log_warn("coerced 3 rows")
}

run_section("A. default -- no timestamp, output unchanged")

run_section("B. format = \"%H:%M:%S\" -- the usual interactive choice",
            overrides = list(timestamp = list(format = "%H:%M:%S")))

# Every line kind takes the column, at a fixed left edge: step opens, leaves,
# close lines, group headers and group corners, and with_logging()'s own run
# summary. The tree itself is byte-for-byte what section A printed, just moved
# right by one constant column.

run_section("C. format = \"%Y-%m-%d %H:%M:%S\" -- what a saved log wants",
            overrides = list(timestamp = list(format = "%Y-%m-%d %H:%M:%S")))

# --- D. fixed width ----------------------------------------------------------
# "%B" renders as "March" in one month and "December" in another. Trusting the
# format string's length would shear the tree between those two lines; the
# column is measured from a rendered sample and padded, so it does not.
# ("%-d", the unpadded day-of-month, is the sharper example, but the "-" flag is
# a glibc extension: macOS and Windows render it literally.)
section("D. a variable-width format is padded, not left to shear")
logtree_reset()
logtree_theme("unicode", wrap = FALSE,
              overrides = list(timestamp = list(format = "%B")))
at <- function(x) as.POSIXct(x, tz = "UTC")
cat(logtree:::format_leaf("info", "early in the month", 1L,
                          stamp = at("2026-03-05 10:00:00")), "\n")
cat(logtree:::format_leaf("info", "and late in it", 1L,
                          stamp = at("2026-12-25 10:00:00")), "\n")
cat(logtree:::format_leaf("warning", "both start at the same column", 1L,
                          stamp = at("2026-07-01 10:00:00")), "\n")
logtree_theme("unicode")

# --- E. wrapping -------------------------------------------------------------
# The column is part of the line's width budget, so a wrapped message breaks
# exactly one column-width earlier than it would without one -- and the
# continuation rows carry a *blank* column rather than a repeated time. One
# event happened once.
section("E. wrapping accounts for the column; continuations blank it")
logtree_reset()
logtree_theme("unicode", wrap = 58,
              overrides = list(timestamp = list(format = "%H:%M:%S")))
long <- function() {
  log_step("A step whose label is long enough to need a second row")
  log_info("and a leaf message that also has to wrap somewhere sensible")
}
invisible(long())
logtree_theme("unicode")

# --- F. colour ---------------------------------------------------------------
section("F. color -- the column is supporting detail, so it stays faint")
run_section("F1. the default silver",
            overrides = list(timestamp = list(format = "%H:%M:%S")))
run_section("F2. color = c(\"bold\", \"blue\")",
            overrides = list(timestamp = list(format = "%H:%M:%S",
                                              color = c("bold", "blue"))))

# --- G. the digest is not stamped --------------------------------------------
# logtree_summary() replays events that already happened. Stamping those lines
# with the time the digest was printed would be a lie, so they carry no column.
section("G. the digest carries no timestamp -- it is a replay, not a live line")
logtree_reset()
logtree_theme("unicode",
              overrides = list(timestamp = list(format = "%H:%M:%S")))
with_logging(tree(), summary = FALSE)
logtree_summary()
logtree_theme("unicode")

# --- H. file sinks -----------------------------------------------------------
# A text sink follows the console by default, and pins its own column with
# `timestamp =`: FALSE for none, TRUE for a date-and-time format suited to a
# file that outlives the session, or a format string of your own. A "json" sink
# ignores the argument -- it always carries an ISO-8601 `ts`.
section("H. file sinks: follow the console, or pin their own")
logtree_reset()
logtree_theme("unicode")   # console column off

follows <- tempfile(fileext = ".log")
pinned  <- tempfile(fileext = ".log")
logtree_sink_file(follows, format = "text")
logtree_sink_file(pinned,  format = "text", timestamp = TRUE)
with_logging(tree(), summary = FALSE)

cat("\n-- follows the console (which has no column) --\n")
cat(readLines(follows), sep = "\n")
cat("\n\n-- pinned with timestamp = TRUE --\n")
cat(readLines(pinned), sep = "\n")
cat("\n")

logtree_sink_remove(setdiff(logtree_sinks(), "console"))
logtree_theme("unicode")
logtree_reset()
