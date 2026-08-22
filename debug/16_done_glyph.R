# Theming the close ("Done") tick independently of log_success(). The two ticks
# come from two different theme slots -- `done` for a step's own close line,
# `success` for log_success() leaves -- which merely ship the same glyph in
# every preset. Each section renders the SAME tree so the only difference is
# which slot was restyled.
#
#   source("debug/16_done_glyph.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, fn) {
  section(title)
  logtree_reset()
  logtree_theme("unicode")           # start each section from a clean theme
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(fn(), summary = FALSE)
}

# One clean close, one success leaf, and one warning-elevated close, so all
# three glyph sources are visible at once.
tree <- function() {
  inner <- function() {
    log_step("Validate input")
    log_success("12 parameters ok")
  }
  flaky <- function() {
    log_step("Fetch remote")
    log_warn("retry 1/3 due to timeout")
  }
  log_step("Pipeline")
  inner()
  flaky()
}

# ---------------------------------------------------------------------------
# A. Default: `done` and `success` both render the unicode tick.
run_section("A. default (done == success)", function() {
  tree()
})

# ---------------------------------------------------------------------------
# B. Restyle `done` only -- every "Done" line changes, the success leaf does
#    not. The warning-elevated close still renders the `warning` glyph: `done`
#    only ever governs a *clean* close.
run_section("B. done only", function() {
  logtree_theme(overrides = list(done = list(glyph = "=", color = "silver")))
  tree()
})

# ---------------------------------------------------------------------------
# C. Restyle `success` only -- the leaf changes, the "Done" lines keep the tick.
run_section("C. success only", function() {
  logtree_theme(overrides = list(success = list(glyph = "*", color = c("green", "bold"))))
  tree()
})

# ---------------------------------------------------------------------------
# D. Both at once, pulling them visibly apart.
run_section("D. done + success, different glyphs", function() {
  logtree_theme(overrides = list(
    done    = list(glyph = "•", color = "silver"),
    success = list(glyph = "*", color = c("green", "bold"))
  ))
  tree()
})

# ---------------------------------------------------------------------------
# E. Overrides ride any preset: ascii with a distinct close marker.
run_section("E. ascii preset + custom done", function() {
  logtree_theme("ascii", overrides = list(done = list(glyph = "=")))
  tree()
})
