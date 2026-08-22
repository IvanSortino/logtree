# The `ci` preset: built for log capture rather than a terminal.
#
#   logtree_theme("ci")
#
#   * bracketed word glyphs -- [step] [info] [debug] [ok] [done] [warn]
#     [fail] [break] -- so a failure greps as "[fail]"
#   * pure-ASCII connectors, with a distinct corner ("\-") so a closed subtree
#     is still obvious in a wall of captured output
#   * no colour in any slot, because CI runners strip ANSI
#   * wordless close lines: "[done] Done" would say it twice
#
# The words are different lengths on purpose. Each declares its true width, so
# theme_slot_width() pads them and the message column still lines up --
# section C proves it.
#
#   source("debug/21_ci_preset.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, theme, ...) {
  section(title)
  logtree_reset()
  logtree_theme(theme, ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = FALSE)
}

tree <- function() {
  log_step("build")
  compile <- function() {
    log_step("compile")
    log_info("linking objects")
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

run_section("A. unicode (default)", "unicode")
run_section("B. ci -- words instead of symbols, no colour", "ci")

# The point of the preset: outcomes are greppable words, not glyphs you cannot
# type into a search box.
section("C. greppable, and the message column still lines up")
logtree_theme("ci")
for (s in c("info", "debug", "success", "warning", "error", "interrupted")) {
  cat(format_leaf(s, "message starts here", 1L, color = FALSE), "\n", sep = "")
}
cat("\nwidest glyph is ", theme_slot_width(),
    " columns, so every message starts at column ",
    theme_slot_width() + theme_glyph_gap() + tree_col_width() + 1L, "\n", sep = "")
logtree_theme("unicode")

# ci emits no ANSI at all, so a captured log is byte-identical whether or not
# the runner has a TTY. Compare against unicode, which does colour.
section("D. no ANSI escapes, even with colour forced on")
withr::with_options(list(cli.num_colors = 256), {
  logtree_theme("unicode")
  u <- format_leaf("error", "boom", 1L)
  logtree_theme("ci")
  c_ <- format_leaf("error", "boom", 1L)
  cat("unicode: ", encodeString(u), "\n", sep = "")
  cat("ci     : ", encodeString(c_), "\n", sep = "")
  cat("ci has escapes: ", grepl("\033", c_, fixed = TRUE), "\n", sep = "")
})
logtree_theme("unicode")

# An uncaught error under with_logging(): every open step is marked [fail],
# which is exactly what you want to find when scrolling a failed build.
section("E. a failing run")
logtree_reset()
logtree_theme("ci")
failing <- function() {
  log_step("deploy")
  push <- function() {
    log_step("push image")
    stop("registry unreachable")
  }
  push()
}
try(with_logging(failing()), silent = TRUE)
logtree_summary()

# Groups render with the ascii-style < brackets >.
section("F. groups")
logtree_reset()
logtree_theme("ci")
suite <- function(i) log_step(paste0("test ", i),
                              group = stats::setNames(i, paste0("Suite ", i)))
runner <- function() { suite(1); suite(1); suite(2) }
runner()

logtree_theme("unicode")
logtree_reset()
