# compact theme: reduce the tree's per-level indentation via
# `logtree_theme(compact = ...)`. Each section renders the SAME nested tree so
# the only difference is the density:
#   FALSE (default) -> 3 columns / level
#   "medium"        -> 2 columns / level (trailing gap dropped)
#   "tight"         -> 1 column  / level (connectors also slimmed to 1 char)
#
# `connector_gap` is independent of `compact`: it spaces a *leaf or close*
# line's own connector from its status glyph -- never a step-open line's,
# which always renders flush -- so "tight" rails stay flush everywhere except
# leaf/close glyphs, e.g. `│├ ` instead of `│├` before the glyph.
#
#   source("debug/15_compact_theme.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, compact, connector_gap = NULL) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", compact = compact, connector_gap = connector_gap)
  on.exit(logtree_theme("unicode"), add = TRUE)  # clear compact afterwards
  with_logging(tree(), summary = FALSE)
}

# Depth 1-3 plus a group, so every per-level column is visible: build > compile
# > (info + warn leaves), then two grouped test steps under < Suite 1 >.
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

run_section("A. default (compact = FALSE)", FALSE)
run_section("B. compact = \"medium\"", "medium")
run_section("C. compact = \"tight\"", "tight")
run_section("D. compact = \"tight\", connector_gap = 1", "tight", connector_gap = 1)

cat("\n")
