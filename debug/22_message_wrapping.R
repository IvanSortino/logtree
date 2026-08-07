# Message wrapping: `logtree_theme(wrap = ...)` caps a rendered line at a
# column budget instead of letting long text run off the right edge.
#
#   wrap = FALSE   -- never wrap (the default; output is unchanged)
#   wrap = TRUE    -- wrap at cli::console_width(), measured at render time
#   wrap = 60      -- wrap at a fixed 60 columns
#
# Continuation lines indent to the message column and carry the rails down, so
# a wrapped message still reads as one node of the tree. After a branch
# connector the rail continues (more siblings may follow); after a corner it
# does not, since nothing comes below it at that column.
#
#   source("debug/22_message_wrapping.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
ruler <- function(n) {
  cat("\033[2m", substr(strrep("....|....:", 20), 1, n), " <- ", n,
      " columns\033[0m\n", sep = "")
}
run_section <- function(title, ..., width = NULL) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  if (!is.null(width)) ruler(width)
  with_logging(tree(), summary = FALSE)
}

# Messages long enough to need wrapping at depths 1-3, so the rails on the
# continuation lines are visible.
tree <- function() {
  log_step("deploy the production release candidate to the staging cluster")
  push <- function() {
    log_step("push image")
    log_info("uploading layers to the internal registry at registry.example.internal, 412 MB across 14 layers")
    log_warn("the manifest declares a base image that has not been rebuilt in 94 days")
  }
  push()
  verify <- function() {
    log_step("verify")
    log_error("the readiness probe never returned healthy: 30 consecutive timeouts over 5 minutes")
  }
  verify()
}

run_section("A. wrap = FALSE (default) -- lines run off the edge", width = 60)
run_section("B. wrap = 60 -- word-wrapped, rails carried down", wrap = 60, width = 60)
run_section("C. wrap = 44 -- tighter budget", wrap = 44, width = 44)

# TRUE re-measures every time a line is rendered, so resizing the terminal
# mid-run is picked up without touching the theme again.
section("D. wrap = TRUE follows the console width")
logtree_theme("unicode", wrap = TRUE)
for (w in c(50, 70)) {
  withr::with_options(list(cli.width = w), {
    cat("\ncli.width = ", w, " -> theme_wrap_width() = ", theme_wrap_width(),
        "\n", sep = "")
    ruler(w)
    logtree_reset()
    with_logging(tree(), summary = FALSE)
  })
}
logtree_theme("unicode")

# A token with no space in it -- a path, a URL, a hash -- is hard-split by
# display width so it cannot overflow the budget either.
section("E. an unbreakable token is split by width, not left to overflow")
logtree_reset()
logtree_theme("unicode", wrap = 46)
ruler(46)
paths <- function() {
  log_step("resolve")
  log_info("/opt/pipeline/artifacts/2026-08-07/build-4821/target/release/deps/libpipeline_core.rlib")
}
paths()
logtree_reset()

# Every line kind wraps to its own message column: step open, leaf, close, and
# the group header (whose column is the marker, not a status glyph).
section("F. group headers and close lines wrap too")
logtree_reset()
logtree_theme("unicode", wrap = 40,
              overrides = list(done = list(text = "finished the whole of this step")))
ruler(40)
grouped <- function(i) {
  log_step(paste0("case ", i),
           group = stats::setNames(i, "A group whose name is far too long for one line"))
}
runner <- function() { grouped(1); grouped(1) }
runner()
logtree_reset()

# The digest and the run-summary line go through the same wrapping, so `wrap`
# covers every line logtree renders -- not just the tree.
section("G. the summary digest wraps as well")
logtree_reset()
logtree_theme("unicode", wrap = 44)
ruler(44)
try(with_logging(tree()), silent = TRUE)
logtree_summary()
logtree_theme("unicode")

# File sinks render through the ascii preset, which carries no `wrap`: a file
# has no width to wrap to, so the log keeps one event per line.
section("H. file sinks are never wrapped")
path <- tempfile(fileext = ".log")
logtree_reset()
logtree_theme("unicode", wrap = 40)
logtree_sink_file(path, format = "text")
with_logging(tree(), summary = FALSE)
cat("\n-- ", path, " (one line per event) --\n", sep = "")
cat(readLines(path), sep = "\n")
cat("\n")

logtree_theme("unicode")
logtree_reset()
