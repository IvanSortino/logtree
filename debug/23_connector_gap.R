# connector_gap: the spaces between a leaf or close line's OWN connector and
# its status glyph, set via `logtree_theme(connector_gap = ...)`.
#
# logtree has three horizontal knobs, and this is the one in the middle:
#
#   compact       -- the per-level rail column (col_gap + connector width)
#   connector_gap -- a leaf/close line's own connector -> its glyph
#   glyph_gap     -- the glyph -> the message text
#
# Unset, connector_gap tracks col_gap, so every preset and every compact
# density renders exactly as it always did. Set it and it diverges -- which is
# the point: `compact = "tight"` can keep every rail column flush while leaf
# and close glyphs still get air.
#
# It deliberately never touches a step's *open* line (or a group header):
# those are rail columns, not the glyph's own approach, so they stay flush at
# any density. Section C shows that difference directly.
#
#   source("debug/23_connector_gap.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = FALSE)
}

# Depth 1-3 with leaves, a warning and a close line at every level, so the
# connector -> glyph column is visible on each line kind at once.
tree <- function() {
  log_step("build")
  compile <- function() {
    log_step("compile")
    log_info("linking objects")
    log_warn("deprecated flag")
  }
  compile()
  test <- function() {
    log_step("test")
    log_info("42 passed")
  }
  test()
}

run_section("A. default -- connector_gap tracks col_gap")
run_section("B. compact = \"tight\" -- everything flush", compact = "tight")

# The pairing this setting exists for: tight rails, readable glyphs.
run_section("C. tight + connector_gap = 1 -- rails flush, glyphs spaced",
            compact = "tight", connector_gap = 1)
run_section("D. tight + connector_gap = 3", compact = "tight", connector_gap = 3)

# Open lines are rail columns and stay flush; only leaf/close lines take the
# gap. Print them side by side so the asymmetry is explicit rather than
# something you have to infer from the tree above.
section("E. open lines stay flush, leaf/close lines take the gap")
logtree_theme("ascii", compact = "tight", connector_gap = 2)
entry <- list(depth = 2L, label = "Build", glyph = NULL,
              status = "running", elapsed = 0.5)
cat("  step open   : [", format_open(entry, color = FALSE), "]\n", sep = "")
cat("  group header: [",
    format_group_header(list(depth = 2L, name = "Suite 1"), color = FALSE),
    "]\n", sep = "")
cat("  leaf        : [", format_leaf("info", "msg", 2L, color = FALSE), "]\n", sep = "")
cat("  close       : [", format_close(entry, color = FALSE), "]\n", sep = "")
logtree_theme("unicode")

# The gap belongs to the connector's own approach, so it must not compound
# with depth -- each level still advances by exactly one tree column.
section("F. the gap does not compound with depth")
logtree_theme("ascii", compact = "tight", connector_gap = 3)
for (d in 1:4) {
  cat("  depth ", d, ": [", format_leaf("info", "msg", d, color = FALSE), "]\n", sep = "")
}
logtree_theme("unicode")

# All three knobs together, and how they stack on one line.
section("G. all three knobs at once")
logtree_theme("ascii", compact = "tight", connector_gap = 2, glyph_gap = 3)
cat("  [", format_leaf("info", "message", 2L, color = FALSE), "]\n", sep = "")
cat("   rails: 1 col/level | connector_gap: 2 | glyph_gap: 3\n")
logtree_theme("unicode")

# Wrapped continuation lines indent to the message column, which now includes
# connector_gap -- the rails above it are unchanged.
section("H. wrapping lands on the widened message column")
logtree_reset()
logtree_theme("unicode", compact = "tight", connector_gap = 2, wrap = 52)
long <- function() {
  log_step("deploy")
  log_info("uploading layers to the internal registry at registry.example.internal, 412 MB")
}
long()
logtree_reset()

# File sinks render through the ascii preset, which carries no connector_gap,
# so a console setting never reaches the log file.
section("I. file sinks keep their built-in spacing")
path <- tempfile(fileext = ".log")
logtree_reset()
logtree_theme("unicode", compact = "tight", connector_gap = 4)
logtree_sink_file(path, format = "text")
with_logging(tree(), summary = FALSE)
cat("\n-- ", path, " --\n", sep = "")
cat(readLines(path), sep = "\n")
cat("\n")

logtree_theme("unicode")
logtree_reset()
