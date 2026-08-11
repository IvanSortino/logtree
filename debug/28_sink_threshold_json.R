# Per-sink thresholds, and what a "json" sink writes.
#
#   logtree_sink_file(path, format, threshold = )   -- and the same argument on
#   logtree_sink(fn, threshold = )                     logtree_sink_memory()
#
# logtree_threshold() is global: setting it to "debug" so a log file captures
# everything used to drag the console down to debug as well. A sink can pin its
# own level now, and the global one is simply the default for sinks that do not.
#
# Two things fall out of that, both worth understanding:
#
#   * Verbosity is a *rendering* gate. A warning hidden by the threshold still
#     elevates its step's glyph -- it always did -- and now also still reaches
#     the logtree_summary() digest. What is suppressed is the line's text, not
#     the fact that it happened. Section D.
#   * A "json" record carries an ISO-8601 `ts` and a `run_id`, where `ts` used
#     to be a bare epoch number with nothing to say which run it belonged to.
#     Section E.
#
#   Rscript -e 'devtools::load_all(); source("debug/28_sink_threshold_json.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

solo_console <- function() {
  logtree_sink_remove(setdiff(logtree_sinks(), "console"))
  logtree_reset()
  logtree_threshold("info")
}

pipeline <- function() {
  log_step("Pipeline")
  log_debug("cache miss for key user:42")
  log_info("config loaded")
  load_data()
}
load_data <- function() {
  log_step("Load data")
  log_debug("connection pool at 3/8")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}

# --- A. the problem ----------------------------------------------------------
section("A. the console at \"info\" -- debug lines are hidden, as asked")
solo_console()
with_logging(pipeline(), summary = FALSE)

# --- B. a louder file than the console ---------------------------------------
# The file wants everything; the terminal wants a readable summary. Before, you
# had to choose.
section("B. threshold = \"debug\" on the file, console left at \"info\"")
solo_console()
path <- tempfile(fileext = ".log")
logtree_sink_file(path, format = "text", threshold = "debug")
with_logging(pipeline(), summary = FALSE)

cat("\n-- the file, which kept the debug lines --\n")
cat(readLines(path), sep = "\n")
cat("\n")

# --- C. a quieter sink than the console --------------------------------------
# It works in the other direction too: a sink that only ever hears about
# failures, whatever the console is showing.
section("C. threshold = \"error\" -- a sink that only sees failures")
solo_console()
errors <- logtree_sink_memory(threshold = "error")
with_logging({
  pipeline()
  broken <- function() { log_step("Summarise"); log_error("no numeric columns") }
  broken()
}, summary = FALSE)

cat("\n-- what the error-only sink collected --\n")
print(logtree_sink_memory_events(errors)[, c("level", "label", "status")])

# Note the open/close rows in there: step lines are never gated. Hiding those
# would break the tree rather than quieten it.

# --- D. verbosity gates rendering, not remembering ---------------------------
# The threshold hides the warning's text. It does not hide the warning: the
# step still closes with the elevated glyph, and the digest still reports it.
section("D. a suppressed warning still elevates, and still reaches the digest")
solo_console()
logtree_threshold("error")
with_logging(pipeline(), summary = FALSE)
cat("\n-- nothing above says \"coerced 3 rows\"; the digest does --\n")
logtree_summary()
logtree_threshold("info")

# --- E. what a json record looks like now ------------------------------------
section("E. the \"json\" sink: ISO-8601 ts, and a run id")
solo_console()
json <- tempfile(fileext = ".ndjson")
logtree_sink_file(json, format = "json")

with_logging(load_data(), summary = FALSE)
with_logging(load_data(), summary = FALSE)

cat("\n-- first line of each run --\n")
lines <- readLines(json)
cat(lines[[1]], "\n")
cat(lines[[length(lines) / 2 + 1]], "\n")

# `run_id` is what makes a shared log file usable: it is regenerated per
# with_logging() call (and per logtree_reset()), so the two runs above can be
# told apart even though they logged exactly the same thing.
if (requireNamespace("jsonlite", quietly = TRUE)) {
  ids <- vapply(lines, function(l) jsonlite::fromJSON(l)$run_id, character(1),
                USE.NAMES = FALSE)
  cat("\ndistinct run ids in the file:", length(unique(ids)), "\n")
}

# It is built from the wall clock, the process id and a session counter (two
# runs can start inside the same millisecond) rather than sampled: a
# logger has no business consuming the RNG stream of a script that has just
# called set.seed().
set.seed(42); expected <- runif(1)
set.seed(42); invisible(logtree:::new_run_id()); got <- runif(1)
cat("RNG stream undisturbed by run id generation:", identical(expected, got), "\n")

solo_console()
