devtools::load_all()

ingest <- function() {
  log_step("Ingest")                     # auto step: closes when ingest() returns
  # group_by collapses items that share a value under one < header >, but the
  # group is only reused once the previous item has CLOSED -- so open/close each
  # by hand here (an auto log_step in this same loop would stay open and nest).
  rows <- c(prices = 24318, stocks = 8790, fx = 512)
  for (name in names(rows)) {
    log_open(name, group_by = c(sources = "feed"))
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


# --- Run 1: completes -- auto steps + grouping + recovered error + manual ---

logtree_reset()

# Fake, deterministic clock so elapsed times are stable + visible. Each now()
# call advances by the next value in a fixed cycle of realistic step durations
# (seconds to minutes), so steps read as genuinely long-running work; longer /
# deeper steps span more now() calls and accrue proportionally more time.
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

with_logging({
  run <- log_open("ETL run")           # manual root (block level)

  ingest()                             # auto step + grouped sub-tree
  connect()                            # auto step + recovered error

  # Manual deep branch: explicit parent links + hand-controlled batches.
  load <- log_open("Load", parent = run)  # sibling of ingest/connect, under run
  log_open("Table: facts")                # under Load (cascade-closed via load)
  log_info("opened connection pool (5 conns)")
  log_open("Batch 1/2", group_by = c(Batches = "load"))   # collapse under < Batches >
  log_info("upserted rows 1-500 of 900")
  log_close()                             # close item; next batch joins the group
  log_open("Batch 2/2", group_by = c(Batches = "load"))
  log_info("upserted rows 501-900 of 900")
  log_close()
  log_close(load)                         # cascade: Batches group + Table + Load

  log_close(run)                          # close the manual root
})
