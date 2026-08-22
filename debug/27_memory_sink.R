# The memory sink: collect events in a buffer instead of writing them anywhere,
# so a run's logging can be asserted on rather than eyeballed.
#
#   logtree_sink_memory(max = 1000)     -- register; returns the sink's id
#   logtree_sink_memory_events(id)      -- read the buffer back as a data frame
#
# The question it answers is "did my pipeline log what it should have?". Before
# this, the only way to check was to capture console output and pattern-match
# the rendered tree -- which couples a test to glyphs, connectors and the active
# theme, none of which the test actually cares about.
#
# The columns are the same ones a "json" file sink writes (script 04), on
# purpose: a run replayed from a log file and the same run inspected in memory
# should say the same things.
#
#   Rscript -e 'devtools::load_all(); source("debug/27_memory_sink.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

solo_console <- function() {
  logtree_sink_remove(setdiff(logtree_sinks(), "console"))
  logtree_reset()
}

pipeline <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  load_data()
  summarise()
}
load_data <- function() {
  log_step("Load data")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}
summarise <- function() {
  log_step("Summarise")
  log_success("3 metrics")
}

# --- A. the shape ------------------------------------------------------------
section("A. one row per event, oldest first")
solo_console()
h <- logtree_sink_memory()
with_logging(pipeline(), summary = FALSE)

events <- logtree_sink_memory_events(h)
cat("\n-- the events --\n")
print(events[, c("level", "depth", "label", "status", "elapsed")])

cat("\n-- and the full schema --\n")
str(events)

# --- B. asserting on it ------------------------------------------------------
# This is the point of the thing: questions about a run, answered against data
# rather than against rendered text.
section("B. what the buffer lets you ask")
leaves <- events[events$level == "leaf", ]
cat("leaf lines logged:      ", nrow(leaves), "\n")
cat("warnings among them:    ", sum(leaves$status == "warning"), "\n")
cat("steps that were opened: ", sum(events$level == "open"), "\n")
cat("did 'Load data' warn?   ",
    any(events$level == "close" & events$label == "Load data" &
          events$status == "warning"), "\n")
cat("slowest step:           ",
    events$label[which.max(ifelse(is.na(events$elapsed), -1, events$elapsed))], "\n")

# --- C. the cap --------------------------------------------------------------
# A long-running process must not grow the buffer without bound, so it keeps the
# most recent `max` events and drops the rest.
section("C. max = keep the last N events")
solo_console()
capped <- logtree_sink_memory(max = 4)
noisy <- function() for (i in 1:10) log_info(sprintf("line %d", i))
invisible(noisy())
cat("\nlabels still in a max = 4 buffer:\n")
print(logtree_sink_memory_events(capped)$label)

# --- D. it is a sink like any other ------------------------------------------
# It sits in the same registry as the console and any file sinks, so it is
# listed, ordered and removed exactly like them -- and removing it drops the
# buffer with it.
section("D. registered, listed and removed like any other sink")
print(logtree_sinks())
logtree_sink_remove(capped)
print(logtree_sinks())
cat("reading a removed sink is an error:\n")
print(tryCatch(logtree_sink_memory_events(capped),
               error = function(e) conditionMessage(e)))

# --- E. call sites, when they were captured ----------------------------------
# `fn` / `file` / `line` are NA unless the `trace` theme slot recorded a call
# site (script 24). `capture = TRUE` records them while printing nothing, which
# pairs well with a memory sink: a quiet tree, and locations in the data.
#
# `file` and `line` stay NA under plain `Rscript` -- they come from source
# references, which need keep.source = TRUE (script 24, section G). `fn` always
# works, and it is the column below that fills in.
section("E. with trace capture on, the records carry call sites")
solo_console()
logtree_theme("unicode", overrides = list(trace = list(show = FALSE,
                                                      capture = TRUE)))
traced <- logtree_sink_memory()
with_logging(pipeline(), summary = FALSE)
cat("\n")
print(logtree_sink_memory_events(traced)[, c("level", "label", "fn", "line")])

logtree_theme("unicode")
solo_console()
