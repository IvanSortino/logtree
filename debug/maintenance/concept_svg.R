if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  devtools::load_all()
}
source("debug/maintenance/ansi_svg.R")

# Regenerates the four concept figures used by the documentation site:
#
#   vignettes/concept-frames.svg      why a step closes when it does
#   vignettes/concept-anatomy.svg     the columns one rendered line is made of
#   vignettes/concept-elevation.svg   a warning bumping its step's glyph
#   vignettes/concept-grouping.svg    adjacency-based grouping
#
# These are figures rather than chunks because each one carries *annotation* --
# callouts, brackets, frame bars -- that ordinary output cannot. pkgdown itself
# renders logtree's colour perfectly well (build_rmarkdown_article() sets
# R_CLI_NUM_COLORS=256), so anything whose point is only "it is coloured" stays
# a plain chunk.
#
#   Rscript -e 'source("debug/maintenance/concept_svg.R")'

withr::local_options(cli.num_colors = 256)

# Every figure here measures box-drawing and status glyphs with nchar() and
# locates them with regexpr(). Under a non-UTF-8 locale both count *bytes*, so
# a "|" rail measures 3 instead of 1 and every bracket and callout silently
# lands in the wrong column. Fail loudly rather than write a broken figure.
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  stop("run this under a UTF-8 locale, e.g. LC_ALL=C.utf8 Rscript -e '...' ",
       "(LC_CTYPE is currently ", Sys.getlocale("LC_CTYPE"), ")")
}

# Deterministic elapsed times, so re-running this does not churn the figures.
freeze_clock <- function(gaps = c(1.4, 2.1, 0.8, 3.6, 1.2)) {
  t <- 0
  i <- 0L
  assignInNamespace("now", function() {
    i <<- i + 1L
    t <<- t + gaps[[(i - 1L) %% length(gaps) + 1L]]
    t
  }, ns = "logtree")
}

# --- 1. frames: why a step closes when it does -------------------------------

pipeline_demo <- function() {
  load_config <- function() {
    log_step("Load config")
    log_info("reading config.yml")
  }
  pipeline <- function() {
    log_step("Pipeline")
    load_config()
  }
  logtree_reset()
  pipeline()
}

logtree_reset()
freeze_clock()
frame_lines <- capture.output(pipeline_demo())

# The trace is written by hand rather than captured, because what it shows --
# frames opening and returning -- leaves no trace in the output. Rows align 1:1
# with the printed lines, and the two rows that print a close line carry no
# log_*() call at all: that is the whole lesson.
trace_rows <- c(
  "pipeline()",
  '  log_step("Pipeline")',
  "  load_config()",
  '    log_step("Load config")',
  '    log_info("reading config.yml")',
  "  # load_config() returns",
  "# pipeline() returns"
)
tree_rows <- c(
  "",                 # the call itself prints nothing
  frame_lines[[1]],   # open: Pipeline
  "",                 # the call itself prints nothing
  frame_lines[[2]],   # open: Load config
  frame_lines[[3]],   # the info leaf
  frame_lines[[4]],   # close: Load config -- drawn by the frame exiting
  frame_lines[[5]]    # close: Pipeline    -- drawn by the frame exiting
)

frames_svg_write(
  trace_rows = trace_rows,
  tree_rows  = tree_rows,
  frames = list(
    list(start = 1, end = 7, label = "pipeline()",    color = palette[["36"]], depth = 0),
    list(start = 3, end = 6, label = "load_config()", color = palette[["35"]], depth = 1)
  ),
  out_path = "vignettes/concept-frames.svg",
  title = "How a logtree step knows when to close",
  label = "An execution trace beside the logtree output it produces, with bars showing each function frame's lifetime"
)

# --- 2. anatomy: the columns of one line -------------------------------------

anatomy_demo <- function() {
  outer <- function() {
    log_step("Extract")
    inner()
  }
  inner <- function() {
    log_step("Parse")
    log_warn("coerced 3 rows to NA")
  }
  logtree_reset()
  outer()
}

logtree_reset()
freeze_clock()
logtree_theme("unicode", overrides = list(
  timestamp = list(format = "%H:%M:%S"),
  trace     = list(show = "problems", format = "{fn}()")
))
anatomy_lines <- capture.output(anatomy_demo())
logtree_theme("unicode")

# The warn leaf: the one line that carries every optional column at once.
warn_line <- grep("coerced", anatomy_lines, value = TRUE)[1]
plain_warn <- strip_ansi(warn_line)
cat("anatomy line: [", plain_warn, "]\n", sep = "")

# Offsets are computed from the plain text rather than hard-coded, so a change
# to spacing or glyph width cannot silently misalign the brackets.
ts_end    <- 9L                                   # "HH:MM:SS "
rails_end <- regexpr("├", plain_warn) - 1L   # up to the branch connector
conn_end  <- rails_end + 3L                       # branch + its trailing space
glyph_end <- conn_end + 2L                        # glyph + its gap
msg_start <- glyph_end
msg_end   <- msg_start + nchar("coerced 3 rows to NA")
trace_beg <- msg_end + 2L

ansi_svg_anatomy(
  warn_line, "vignettes/concept-anatomy.svg",
  columns = list(
    list(from = 0L,         to = ts_end,    label = "timestamp column (opt-in)",  color = palette[["30"]]),
    list(from = ts_end,     to = rails_end, label = "rails: one per open ancestor", color = dim_color),
    list(from = rails_end,  to = conn_end,  label = "connector",                  color = dim_color),
    list(from = conn_end,   to = glyph_end, label = "status glyph",               color = palette[["33"]]),
    list(from = msg_start,  to = msg_end,   label = "message",                    color = default_color),
    list(from = trace_beg,  to = nchar(plain_warn), label = "call site (opt-in)", color = palette[["36"]])
  ),
  title = "Anatomy of a logtree line",
  label = "One logtree line with its timestamp, rails, connector, glyph, message and call-site columns labelled"
)

# --- 3. status elevation -----------------------------------------------------

elevation_demo <- function() {
  parse_rows <- function() {
    log_step("Parse rows")
    log_info("1,200 rows")
    log_warn("coerced 3 rows to NA")
    log_success("parsed")
  }
  load_data <- function() {
    log_step("Load data")
    parse_rows()
  }
  logtree_reset()
  load_data()
}

logtree_reset()
freeze_clock()
elevation_lines <- capture.output(elevation_demo())

ansi_svg_write(
  elevation_lines, "vignettes/concept-elevation.svg",
  annotations = list(
    list(match = "1,200 rows", color = palette[["34"]],
         text = "an info leaf leaves its step alone"),
    list(match = "coerced", color = palette[["33"]],
         text = "log_warn() elevates the nearest open step"),
    list(match = "parsed", color = palette[["32"]],
         text = "a later success cannot undo it — elevation only moves up"),
    # The payoff: the elevated glyph shows up on a line nothing wrote directly.
    list(match = "Done  0.80s", color = palette[["33"]],
         text = "so the step closes warned, having never thrown")
  ),
  title = "Status elevation",
  label = "A logtree tree where a warning leaf elevates its enclosing step's close glyph"
)

# --- 4. grouping is adjacency-based ------------------------------------------

grouping_demo <- function() {
  load_file <- function(dataset, file) {
    log_step(file, group = dataset)
    log_success("merged")
  }
  import <- function() {
    log_step("Import")
    load_file("sales",   "2023.csv")
    load_file("sales",   "2024.csv")
    load_file("returns", "2024.csv")
    load_file("sales",   "2025.csv")
  }
  logtree_reset()
  import()
}

logtree_reset()
freeze_clock()
grouping_lines <- capture.output(grouping_demo())

ansi_svg_write(
  grouping_lines, "vignettes/concept-grouping.svg",
  annotations = list(
    list(match = "2023.csv", color = palette[["35"]],
         text = "adjacent steps sharing a value collapse under one header"),
    list(match = "returns", color = palette[["35"]],
         text = "a different value settles the open group and starts a new one"),
    list(match = "sales", nth = 2L, color = palette[["31"]],
         text = "sales recurs, but not adjacently — so it opens a fresh header")
  ),
  title = "Grouping is adjacency-based",
  label = "A logtree tree showing adjacent steps grouped under one header and a non-adjacent recurrence opening a second"
)
