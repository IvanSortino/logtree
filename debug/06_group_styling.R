# Styling the group < name > header via the `group` theme slot. Each section
# resets state + theme and runs the same little grouped tree so the styling
# change is the only difference.
#
#   source("debug/06_group_styling.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, fn) {
  section(title)
  logtree_reset()
  logtree_theme("unicode")          # start each section from a clean theme
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(fn(), summary = FALSE)
}

# The tree every section renders: two items, two steps each, under < Item N >.
grouped <- function() {
  step <- function(i, name) log_step(name, group = stats::setNames(i, paste0("Item ", i)))
  log_step("Pipeline")
  for (i in 1:2) { step(i, "validate"); step(i, "bounds") }
}

# ---------------------------------------------------------------------------
# A. Default: square glyph (▣) in magenta, no brackets.
run_section("A. default group header", function() {
  grouped()
})

# ---------------------------------------------------------------------------
# B. bracket = TRUE -- wrap the header name back in < >.
run_section("B. bracket on", function() {
  logtree_theme(overrides = list(group = list(bracket = TRUE)))
  grouped()
})

# ---------------------------------------------------------------------------
# C. Swap the folder for another glyph -- still no brackets.
run_section("C. glyph override (diamond)", function() {
  logtree_theme(overrides = list(group = list(glyph = "◆")))
  grouped()
})

# ---------------------------------------------------------------------------
# D. Glyph + colour + brackets together.
run_section("D. glyph + color + bracket", function() {
  logtree_theme(overrides = list(group = list(glyph = "▶", color = "cyan", bracket = TRUE)))
  grouped()
})

# ---------------------------------------------------------------------------
# E. Overrides ride any preset: ascii keeps brackets by default (no emoji);
#    here we add a glyph + colour on top.
run_section("E. ascii preset + styled group", function() {
  logtree_theme("ascii", overrides = list(group = list(glyph = "#", color = "green")))
  grouped()
})
