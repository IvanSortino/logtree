devtools::load_all()
source("debug/maintenance/ansi_svg.R")

# Regenerates the two figures used by the "Timestamps and routed conditions"
# article (vignettes/articles/timestamps-and-conditions.Rmd):
#
#   vignettes/articles/timestamp-silver.svg    the wall-clock column, in silver
#   vignettes/articles/routed-conditions.svg   warning()/message() routed in
#
# They sit next to the article rather than in man/figures/ because
# vignettes/articles/ is .Rbuildignore'd: the site shows them, the built
# package does not carry them.
#
# pkgdown evaluates article chunks with no terminal attached, so cli emits no
# ANSI and the rendered output on the site is monochrome. Both features are
# *about* a colour -- a column faint enough to stay out of the way, a warning
# that turns its step yellow -- so the article shows a rendered SVG of the real
# ANSI alongside the plain chunk output.
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

ansi_svg_write(
  ts_lines, "vignettes/articles/timestamp-silver.svg",
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
  routed_lines, "vignettes/articles/routed-conditions.svg",
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
