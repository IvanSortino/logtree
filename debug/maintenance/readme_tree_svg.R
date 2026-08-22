devtools::load_all()
source("debug/maintenance/ansi_svg.R")

# Regenerates man/figures/README-tree-color.svg, the colorized companion to
# the plain ```ansi tree in README.Rmd. GitHub strips inline `style` from
# Markdown HTML and doesn't render ANSI in README code blocks, so an <img>
# of a rendered SVG is the only way to show the real theme colors there.
#
# Runs the actual ETL example through with_logging() with a fake clock (so
# elapsed times are deterministic), captures the real ANSI this package
# emits (forcing color via cli.num_colors since Rscript is non-interactive),
# and hands it to ansi_svg_write() (debug/maintenance/ansi_svg.R), which
# parses the SGR codes back into (text, color) runs and lays them out.

withr::local_options(cli.num_colors = 256)

ingest <- function() {
  log_step("Ingest")                     # auto step: closes when ingest() returns
  rows <- c(prices = 24318, stocks = 8790, fx = 512)
  for (name in names(rows)) {
    log_open(name, group = c(sources = "feed"))
    log_info(sprintf("%s rows pulled", format(rows[[name]], big.mark = ",")))
    log_close()   # close this item; the next one joins the same group
  }
}

connect <- function() {
  log_step("Connect primary")
  log_error("primary db unreachable (timeout after 5s)")  # RECOVERED: logged, keep going
  log_info("failing over to replica db-2")
  log_success("connected to replica, 12ms latency")
  log_close(status = "success")          # override: recovered, so glyph reads success
}


logtree_reset()

local({
  t <- 0
  i <- 0L
  gaps <- c(4.2, 58, 12.5, 143, 9.1, 271, 21, 87)  # seconds per now() tick
  assignInNamespace("now", function() {
    i <<- i + 1L
    t <<- t + gaps[[(i - 1L) %% length(gaps) + 1L]]
    t
  }, ns = "logtree")
})



ansi_lines <- capture.output({
  with_logging({
    run <- log_open("ETL run")           # manual root (block level)

    ingest()                             # auto step + grouped sub-tree
    connect()                            # auto step + recovered error

    # Manual deep branch: explicit parent links + hand-controlled batches.
    load <- log_open("Load", parent = run)  # sibling of ingest/connect, under run
    log_open("Table: facts")                # under Load (cascade-closed via load)
    log_info("opened connection pool (5 conns)")
    log_open("Batch 1/2", group = c(Batches = "load"))   # collapse under < Batches >
    log_info("upserted rows 1-500 of 900")
    log_close()                             # close item; next batch joins the group
    log_open("Batch 2/2", group = c(Batches = "load"))
    log_info("upserted rows 501-900 of 900")
    log_close()
    log_close(load)                         # cascade: Batches group + Table + Load

    log_close(run)                          # close the manual root
  })

  logtree_summary()                      # breadcrumb digest of the recovered error
})

annotations <- list(
  list(match = "ETL run",      color = palette[["36"]], text = "open step — runs on ▶, closes ✔"),
  list(match = "sources",      color = palette[["35"]], text = "group header: adjacent steps collapse here"),
  list(match = "24,318",       color = palette[["34"]], text = "info leaf line"),
  list(match = "Done  1m 27s", color = palette[["32"]], text = "elapsed time, tracked per step"),
  list(match = "unreachable",  color = palette[["31"]], text = "error leaf elevates the step — run keeps going"),
  list(match = "12ms latency", color = palette[["32"]], text = "… then closes ✔ once recovered"),
  list(match = "Run complete", color = palette[["32"]], text = "run summary line (with_logging)"),
  list(match = "Summary:",     color = dim_color,        text = "digest of warnings/errors (logtree_summary)")
)

ansi_svg_write(ansi_lines, "man/figures/README-tree-color.svg",
               annotations = annotations)
