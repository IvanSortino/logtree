# glyph gap: the spacing between a line's status glyph and its message, set via
# `logtree_theme(glyph_gap = ...)`. Each section renders the SAME nested tree so
# the only difference is that one column:
#   1 (built-in) -> "* Reading config.yml"
#   0            -> "*Reading config.yml"      (tightest, minimal look)
#   2            -> "*  Reading config.yml"    (roomier message column)
#
# It composes with `compact`, which controls the *other* horizontal knob (the
# per-level tree column) -- section D pairs the two for the densest output.
#
#   source("debug/17_glyph_gap.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)                  # glyph_gap rides the preset
  on.exit(logtree_theme("unicode"), add = TRUE)  # clear it afterwards
  with_logging(tree(), summary = FALSE)
}

# Depth 1-3 plus a group, so the glyph column is visible on every line kind:
# step open, leaf, group header, and the Done (close) lines.
tree <- function() {
  log_step("build")
  compile <- function() {
    log_step("compile")
    log_info("linking objects")
    log_warn("deprecated flag")
  }
  compile()
  test <- function(i) log_step(paste0("test ", i), group = stats::setNames(i, paste0("Suite ", i)))
  test(1); test(1)
}

run_section("A. default (glyph_gap = 1)")
run_section("B. glyph_gap = 0", glyph_gap = 0)
run_section("C. glyph_gap = 2", glyph_gap = 2)
run_section("D. glyph_gap = 0 + compact = \"tight\"", glyph_gap = 0, compact = "tight")

# File sinks are deliberately unaffected: they render through the ascii preset,
# which carries no glyph_gap, so a console setting never leaks into a log file.
section("E. file sink keeps the built-in spacing")
path <- tempfile(fileext = ".log")
logtree_reset()
logtree_theme("unicode", glyph_gap = 3)
logtree_sink_file(path, format = "text")
with_logging(tree(), summary = FALSE)
cat("\n-- ", path, " --\n", sep = "")
cat(readLines(path), sep = "\n")
cat("\n")
logtree_theme("unicode")
logtree_reset()
