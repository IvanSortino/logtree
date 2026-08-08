# Message wrapping: `logtree_theme(wrap = ...)` caps a rendered line at a
# column budget instead of letting long text run off the right edge. The
# console wraps at its own width out of the box; `wrap` is how you change or
# switch off that budget.
#
#   wrap = TRUE    -- wrap at cli::console_width(), measured at render time
#                     (the console default)
#   wrap = 60      -- wrap at a fixed 60 columns
#   wrap = FALSE   -- never wrap; long lines run off the edge
#
# Continuation lines indent to the message column and carry the rails down, so
# a wrapped message still reads as one node of the tree. After a branch
# connector the rail continues (more siblings may follow); after a corner it
# does not, since nothing comes below it at that column. A step-open line and
# a group header also rail their own glyph/marker column -- that is where
# their children hang -- while a leaf leaves it blank, nothing being nested
# under a leaf. Section I walks the three cases side by side.
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

run_section("A. wrap = FALSE -- lines run off the edge", wrap = FALSE, width = 60)
run_section("B. wrap = 60 -- word-wrapped, rails carried down", wrap = 60, width = 60)
run_section("C. wrap = 44 -- tighter budget", wrap = 44, width = 44)

# TRUE -- what a fresh session and every preset swap start from -- re-measures
# every time a line is rendered, so resizing the terminal mid-run is picked up
# without touching the theme again.
section("D. wrap = TRUE (the default) follows the console width")
logtree_theme("unicode")
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

# Which column a continuation rails is decided by what can appear below it.
# An open line's glyph column is exactly where its children's connectors land,
# so it rails and the wrapped label stays tied to the subtree under it -- on a
# depth-1 root, that is the only rail the line has. A leaf's glyph column
# rails nothing (a leaf has no children) and a corner's column rails nothing
# either (the section is over), so both stay blank.
section("I. an open line rails its glyph column, a leaf does not")
logtree_reset()
logtree_theme("unicode", wrap = 42,
              overrides = list(done = list(text = "finished the whole of this step")))
ruler(42)
rails_demo <- function() {
  log_step("root step whose label is long enough to wrap")
  middle <- function() {
    log_step("middle step whose label also has to wrap")
    log_info("a leaf message long enough to need a second line")
  }
  middle()
}
with_logging(rails_demo(), summary = FALSE)
cat("\n\033[2m",
    "  root/middle continuations rail (children hang there);\n",
    "  the leaf's and the close lines' do not.\033[0m\n", sep = "")

# The group marker column behaves the same way: members hang from it, so the
# wrapped name rails down into them. A preset with no marker at all (ascii,
# minimal) has no column to spare -- the name starts where the members'
# connectors will -- so its continuation stays flush instead.
section("J. a group's marker column rails into its members")
logtree_reset()
logtree_theme("unicode", wrap = 38)
ruler(38)
runner()
logtree_reset()

logtree_theme("unicode")
logtree_reset()
