if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  devtools::load_all()
}
source("debug/maintenance/ansi_svg.R")

# nchar()/regexpr() count bytes under a non-UTF-8 locale, which silently puts
# every callout in the wrong column. See concept_svg.R for the same guard.
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  stop("run this under a UTF-8 locale, e.g. LC_ALL=C.utf8 Rscript -e '...' ",
       "(LC_CTYPE is currently ", Sys.getlocale("LC_CTYPE"), ")")
}

# Regenerates two figures used by the documentation site:
#
#   vignettes/timestamp-silver.svg    the wall-clock column, in silver
#                                       (vignettes/articles/themes.Rmd)
#   vignettes/routed-conditions.svg   warning()/message() routed in
#                                       (vignettes/logtree.Rmd)
#
# Every figure a vignette or article references lives in vignettes/ and is
# referenced by bare filename. The Get started guide is a real vignette, and a
# vignette's images have to sit beside it: its HTML is built into inst/doc/,
# which man/figures/ is not copied alongside, so "../man/figures/..." would
# resolve on the pkgdown site and nowhere else. Articles can share the same
# files because pkgdown renders vignettes/ and vignettes/articles/ into one
# output directory, so the bare name resolves from either.
#
# man/figures/ is for README and index.Rmd assets only.
#
# Note that these are NOT here because pkgdown cannot show colour: it can.
# pkgdown's build_rmarkdown_article() sets R_CLI_NUM_COLORS=256, so cli emits
# real ANSI in article chunks and pkgdown converts it to HTML. These two are
# rendered SVGs because they carry *annotations* -- callouts pointing at the
# line that makes the point -- which chunk output cannot do, and because the
# README needs them too and GitHub renders neither ANSI nor inline style.
#
#   Rscript -e 'source("debug/maintenance/article_svg.R")'

withr::local_options(cli.num_colors = 256)

# Deterministic figures: freeze both clocks. now() is the process clock the
# elapsed column is measured with; wall_clock() is what the timestamp column
# prints. They answer different questions, so they are mocked separately --
# wall_clock() reads the accumulated offset without advancing it, or the stamp
# would jump by each gap twice.
freeze_clocks <- function(start = "2026-02-11 02:14:07",
                          gaps = c(1.4, 2.1, 0.8, 3.6, 1.2)) {
  t <- 0
  i <- 0L
  assignInNamespace("now", function() {
    i <<- i + 1L
    t <<- t + gaps[[(i - 1L) %% length(gaps) + 1L]]
    t
  }, ns = "logtree")
  base <- as.POSIXct(start, tz = "UTC")
  assignInNamespace("wall_clock", function() base + t, ns = "logtree")
}

# --- 1. the timestamp column -------------------------------------------------

etl <- function() {
  log_step("Nightly ETL")
  log_info("config loaded from etl.yml")
  extract()
}

extract <- function() {
  log_step("Extract")
  log_info("24,318 rows pulled")
  log_success("staged to warehouse")
}

logtree_reset()
freeze_clocks()
logtree_theme("unicode", overrides = list(timestamp = list(format = "%H:%M:%S")))

ts_lines <- capture.output(with_logging(etl()))

logtree_theme("unicode")

# Written twice, once beside each document that shows it. pkgdown validates an
# image path relative to its article's own source directory, so a single copy
# in vignettes/ would warn on every build of the cookbook even though both
# articles render into one output directory and the bare name resolves there.
# Both copies come from this one call, so they cannot drift.
for (ts_path in c("vignettes/timestamp-silver.svg",
                  "vignettes/articles/timestamp-silver.svg")) {
ansi_svg_write(
  ts_lines, ts_path,
  # "%H:%M:%S" plus its single trailing space: the column the tree starts after.
  lead = 9L,
  annotations = list(
    list(match = "Nightly ETL", color = palette[["30"]],
         text = "the timestamp column, silver by default"),
    list(match = "24,318",      color = palette[["30"]],
         text = "every line kind carries it, at one fixed left edge"),
    list(match = "staged",      color = palette[["32"]],
         text = "the stamp says when — the elapsed column says how long"),
    list(match = "Run complete", color = palette[["32"]],
         text = "the run summary line is stamped too")
  ),
  title = "logtree timestamp column",
  label = "logtree console output with a silver wall-clock timestamp column"
)
}

# --- 2. routed conditions ----------------------------------------------------

parse_batch <- function() {
  log_step("Parse batch")
  message("using cached schema")          # -> log_info() leaf
  warning("3 rows coerced to NA")         # -> log_warn() leaf, elevates the step
  log_success("1,200 rows parsed")
}

logtree_reset()
freeze_clocks()

routed_lines <- capture.output({
  with_logging(parse_batch(), warnings = TRUE)
  logtree_summary()
})

ansi_svg_write(
  routed_lines, "vignettes/routed-conditions.svg",
  annotations = list(
    list(match = "cached schema", color = palette[["34"]],
         text = "message() becomes an info leaf, at the depth it happened"),
    list(match = "coerced",       color = palette[["33"]],
         text = "warning() becomes a warn leaf — muffled, not re-raised"),
    list(match = "Done",          color = palette[["33"]],
         text = "and it elevates its step, exactly as log_warn() does"),
    list(match = "Summary:",      color = dim_color,
         text = "so it reaches the digest like any other warning")
  ),
  title = "R conditions routed into the logtree tree",
  label = "logtree console output with warning() and message() routed into the tree"
)

# --- 3. the call-site column -------------------------------------------------
#
# The one figure here that a chunk could not have produced even in principle.
# `{file}` and `{line}` come from source references, which knitr's chunks do
# not carry -- an article chunk can only ever show `fn()` -- and the printed
# path is relative to the working directory. So the demo is written to a real
# file inside a throwaway project and run from there, which is what makes the
# figure read "R/pipeline.R:9": the same shape a reader sees from their own
# package, rather than a tempdir path.
trace_src <- c(
  'load_data <- function() {',
  '  log_step("Load data")',
  '  log_info("reading warehouse.parquet")',
  '  parse_rows()',
  '}',
  '',
  'parse_rows <- function() {',
  '  log_step("Parse rows")',
  '  log_warn("coerced 3 rows to NA")',
  '  log_success("1,200 rows")',
  '}'
)

trace_lines <- local({
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "R"))
  writeLines(trace_src, file.path(dir, "R", "pipeline.R"))
  withr::local_dir(dir)
  withr::local_options(keep.source = TRUE)

  env <- new.env(parent = globalenv())
  sys.source(file.path("R", "pipeline.R"), envir = env, keep.source = TRUE)

  logtree_reset()
  freeze_clocks()
  logtree_theme("unicode", overrides = list(trace = list(show = TRUE)))
  on.exit(logtree_theme("unicode"), add = TRUE)

  # A location is also a terminal hyperlink. OSC 8 has no printable width but
  # it is not an SGR sequence either, so it is stripped rather than handed to
  # the parser -- the figure shows the styling, and the text says what the
  # link does.
  gsub("\033]8;;[^\a]*\a", "", capture.output(env$load_data()))
})

ansi_svg_write(
  trace_lines, "vignettes/articles/trace-column.svg",
  annotations = list(
    list(match = "Load data", color = palette[["30"]],
         text = "the location: file and line styled and linked as one unit"),
    list(match = "warehouse", color = palette[["36"]],
         text = "the function name is its own part, coloured apart from it"),
    list(match = "coerced",   color = palette[["33"]],
         text = "show = \"problems\" marks these lines and leaves the rest bare"),
    list(match = "Done",      color = dim_color,
         text = "an ordinary close carries none: its site is its open line's")
  ),
  title = "logtree call-site column",
  label = "logtree console output with a call-site column showing file, line and function name"
)
