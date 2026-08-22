# The `minimal` preset: a tree with no tree drawing. `branch`, `corner` and
# `pipe` are empty strings, so a level costs nothing but its `col_gap` (2) and
# depth is carried by indentation alone.
#
#   logtree_theme("minimal")
#
# It also ships a lighter glyph vocabulary, dimmed elapsed times, no group
# marker, and wordless close lines (`done$text = ""`), so a closing step is
# just a tick and a time.
#
# The trade: info, debug and interrupted all render the middle dot and are
# told apart by colour alone. That is deliberate -- section D shows it.
#
#   source("debug/20_minimal_preset.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, theme, ...) {
  section(title)
  logtree_reset()
  logtree_theme(theme, ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = FALSE)
}

# Depth 1-3 plus every status, so the indentation and the whole glyph set are
# visible at once.
tree <- function() {
  log_step("build")
  compile <- function() {
    log_step("compile")
    log_info("linking objects")
    log_debug("cache hit ratio 0.82")
    log_success("320 objects")
  }
  compile()
  lint <- function() {
    log_step("lint")
    log_warn("2 style violations")
  }
  lint()
  test <- function() {
    log_step("test")
    log_error("3 assertions failed")
  }
  test()
}

# Side by side with the default, so the difference is the point.
run_section("A. unicode (default) -- connectors draw the tree", "unicode")
run_section("B. minimal -- indentation draws the tree", "minimal")

section("C. how the levels are built")
logtree_theme("minimal")
cat("branch glyph : ", encodeString(the$theme$branch$glyph, quote = "\""), "\n", sep = "")
cat("corner glyph : ", encodeString(the$theme$corner$glyph, quote = "\""), "\n", sep = "")
cat("pipe glyph   : ", encodeString(the$theme$pipe$glyph, quote = "\""), "\n", sep = "")
cat("col_gap      : ", theme_col_gap(), "\n", sep = "")
cat("column/level : ", tree_col_width(), "  (0-width connector + col_gap)\n", sep = "")
cat("rail unit    : ", encodeString(rail_unit(color = FALSE), quote = "\""), "\n", sep = "")
logtree_theme("unicode")

# debug is only rendered at the "debug" threshold, so section B hid it. Turn
# the threshold down and the three dotted statuses appear together -- same
# glyph, different colour.
section("D. the trade: info / debug / interrupted share the middle dot")
logtree_reset()
logtree_theme("minimal")
# No on.exit() here: at the top level of a sourced script it fires as soon as
# the expression finishes, which would put the threshold back before demo()
# ever ran. The reset is an explicit call after the demo instead.
logtree_threshold("debug")
demo <- function() {
  log_step("statuses")
  log_info("info -- blue")
  log_debug("debug -- silver")
  log_success("success -- green")
  log_warn("warning -- yellow")
  log_error("error -- red")
}
demo()
logtree_threshold("info")

# An interrupted step (abnormal exit, no with_logging handler) is the fourth
# dotted status -- dimmed rather than coloured.
section("E. an interrupted step is the dimmed dot")
logtree_reset()
logtree_theme("minimal")
boom <- function() {
  log_step("risky")
  stop("kaboom")
}
try(boom(), silent = TRUE)
logtree_reset()

# Grouping still works; the preset simply draws no marker before the header.
section("F. groups carry no marker, just the name")
logtree_reset()
logtree_theme("minimal")
suite <- function(i) log_step(paste0("test ", i),
                              group = stats::setNames(i, paste0("Suite ", i)))
runner <- function() { suite(1); suite(1); suite(2) }
runner()
logtree_summary()

logtree_theme("unicode")
logtree_reset()
