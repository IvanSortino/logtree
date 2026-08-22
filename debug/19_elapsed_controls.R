# Elapsed-time controls: the `elapsed` theme slot decides whether a close
# line's time is shown at all, and how it is coloured.
#
#   show       -- FALSE drops the time column entirely
#   min        -- hide anything faster than N seconds (kills the "0.00s" noise)
#   color      -- cli styles for the time
#   slow       -- times at or over N seconds count as slow
#   slow_color -- cli styles used instead of `color` when a time is slow
#
# It is an ordinary override slot, so it goes through logtree_theme()'s
# `overrides` like any glyph slot -- no new argument.
#
#   source("debug/19_elapsed_controls.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = FALSE)
}

# A deliberately lopsided tree: two steps that finish instantly and one that
# sleeps past a second, so the `min` and `slow` thresholds both have something
# to bite on.
tree <- function() {
  log_step("build")
  quick <- function() {
    log_step("read manifest")
    log_info("14 entries")
  }
  quick()
  quick2 <- function() log_step("resolve deps")
  quick2()
  slow <- function() {
    log_step("compile")
    Sys.sleep(1.2)
    log_info("linked 320 objects")
  }
  slow()
}

run_section("A. default -- every time is shown, unstyled")

# The two instant steps lose their "0.00s"; only the real work reports.
run_section("B. min = 0.1 -- hide the trivially fast steps",
            overrides = list(elapsed = list(min = 0.1)))

run_section("C. show = FALSE -- drop the time column entirely",
            overrides = list(elapsed = list(show = FALSE)))

run_section("D. color -- dim every time",
            overrides = list(elapsed = list(color = "silver")))

# Only `compile` crosses the threshold, so only it turns red.
run_section("E. slow = 1 + slow_color -- flag what is worth noticing",
            overrides = list(elapsed = list(color = "silver",
                                            slow = 1, slow_color = "red")))

# The two knobs compose: hide the noise, highlight the outliers, and let
# everything in between render quietly.
run_section("F. min + slow together",
            overrides = list(elapsed = list(min = 0.1, color = "silver",
                                            slow = 1, slow_color = c("red", "bold"))))

# Pairing `show = FALSE` with the close-line `text = ""` of debug/18 leaves a
# glyph-only close line -- the densest close logtree draws.
run_section("G. glyph-only closes (elapsed off + text empty)",
            overrides = list(elapsed = list(show = FALSE),
                             done    = list(text = "")))

# The run-summary line takes the slot's colouring but never its hiding rules:
# "Run complete in <time>" would be a dangling sentence without the time.
section("H. the run summary always prints its own time")
logtree_reset()
logtree_theme("unicode", overrides = list(elapsed = list(show = FALSE, min = 10)))
with_logging(tree(), summary = TRUE)
logtree_theme("unicode")

# File sinks render through the ascii preset with its own `elapsed` slot, so a
# console setting never hides a time in the log file.
section("I. file sink keeps every time")
path <- tempfile(fileext = ".log")
logtree_reset()
logtree_theme("unicode", overrides = list(elapsed = list(show = FALSE)))
logtree_sink_file(path, format = "text")
with_logging(tree(), summary = FALSE)
cat("\n-- ", path, " --\n", sep = "")
cat(readLines(path), sep = "\n")
cat("\n")

logtree_theme("unicode")
logtree_reset()
