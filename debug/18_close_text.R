# Close-line text: the word a step prints when it closes, before its elapsed
# time. It used to be a hard-coded "Done"; it is now the `text` field of a
# theme slot, read from the closing status's own slot first, then from `done`,
# then falling back to "Done":
#
#   done  = list(text = "Complete")   -> renames every close line
#   error = list(text = "Failed")     -> renames only the ones that went wrong
#   done  = list(text = "")           -> drops the word, leaving glyph + time
#
# Two placeholders are expanded: {label} (the step's own label, or a group's
# name) and {elapsed} (the formatted time). A template that places {elapsed}
# itself owns that column -- the time is not appended a second time.
#
#   source("debug/18_close_text.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)   # clear the overrides
  with_logging(tree(), summary = FALSE)
}

# One clean close, one elevated to warning, one elevated to error, plus a
# group close -- so every branch of the lookup chain is visible at once.
tree <- function() {
  log_step("build")
  compile <- function() {
    log_step("compile")
    log_info("linking objects")
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

run_section("A. default -- the built-in \"Done\"")

run_section("B. done text renames every close line",
            overrides = list(done = list(text = "Complete")))

# Only `error` is overridden, so clean and warning closes keep "Done".
run_section("C. per-status text: only failures are renamed",
            overrides = list(error = list(text = "Failed")))

run_section("D. {label} echoes the step's own label",
            overrides = list(done = list(text = "{label} finished")))

run_section("E. {elapsed} inside the template owns the time column",
            overrides = list(done = list(text = "{label} took {elapsed}")))

# The glyph already says "done"; dropping the word leaves glyph + time, which
# is what the `minimal` and `ci` presets ship.
run_section("F. text = \"\" drops the word entirely",
            overrides = list(done = list(text = "")))

# Localisation falls out of the same knob -- one call renames every outcome.
# Accents are written as \u escapes (U+00E9 e-acute, U+00C9 E-acute) so this
# file stays plain ASCII on disk, the same discipline R/glyphs.R follows.
run_section("G. localised close lines", overrides = list(
  done        = list(text = "Termin\u00e9"),
  warning     = list(text = "Termin\u00e9 avec avertissement"),
  error       = list(text = "\u00c9chec"),
  interrupted = list(text = "Interrompu")
))

# `text` is a close-line concern only: a log_error() leaf keeps its own
# message, and file sinks render through the ascii preset with its own text.
section("H. leaves and file sinks are untouched")
path <- tempfile(fileext = ".log")
logtree_reset()
logtree_theme("unicode", overrides = list(done = list(text = "Complete")))
logtree_sink_file(path, format = "text")
with_logging(tree(), summary = FALSE)
cat("\n-- ", path, " (still \"Done\") --\n", sep = "")
cat(readLines(path), sep = "\n")
cat("\n")

logtree_theme("unicode")
logtree_reset()
