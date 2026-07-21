devtools::load_all()

# Mixed logging, deep tree, plus grouping and the two flavours of error.
#
# Mechanisms:
#   * with_logging()          -- top-level wrapper: error handling + run summary
#   * log_step()              -- auto steps inside functions, self-close on
#                                frame exit; nesting follows the call stack
#   * log_open() / log_close()-- manual steps for block-level structure
#   * group_by =              -- collapse adjacent steps under a < header >
#
# Two error flavours:
#   * RECOVERED: log_error() from code that then returns normally -- the leaf
#     is logged, the enclosing step's glyph is elevated to error, and the run
#     CONTINUES. The elevated glyph sticks (worst-status-seen, not final
#     status) unless the caller explicitly overrides it with
#     log_close(status = "success") once it knows recovery actually worked.
#   * FATAL: a step's code actually stop()s -- with_logging marks the open
#     steps failed, logs the error, prints "Run failed", and rethrows, so the
#     run STOPS there.

# --- Steps -----------------------------------------------------------------

ingest <- function() {
  log_step("Ingest")
  # group_by collapses items that share a value under one < header >, but the
  # group is only reused once the previous item has CLOSED -- so open/close each
  # by hand here (an auto log_step in this same loop would stay open and nest).
  for (name in c("prices", "stocks", "fx")) {
    log_open(name, group_by = c(sources = "feed"))
    log_info("rows ok")
    log_close()   # close this item; the next one joins the same group
  }
}

connect <- function() {
  log_step("Connect primary")
  log_error("primary unreachable")     # RECOVERED: logged, we keep going
  log_info("failing over to replica")
  log_success("connected to replica")
  log_close(status = "success")        # override: recovered, so glyph reads success
}

migrate <- function() {
  log_step("Apply migration")
  log_info("adding column users.tier")
  stop("constraint violation on users.email")   # FATAL: propagates out
}

deploy <- function() {
  log_step("Deploy")
  migrate()                            # throws -> run stops here
  log_info("post-deploy checks")       # never reached
}

# --- Run 1: completes -- auto steps + grouping + recovered error + manual ---

logtree_reset()
with_logging({
  run <- log_open("ETL run")           # manual root (block level)

  ingest()                             # auto step + grouped sub-tree
  connect()                            # auto step + recovered error

  # Manual deep branch: explicit parent links + hand-controlled batches.
  load <- log_open("Load", parent = run)  # sibling of ingest/connect, under run
  tbl  <- log_open("Table: facts")        # under Load
  log_info("open connection")
  log_open("Batch 1/2")                   # under Table
  log_info("rows 1-500")
  log_open("Batch 2/2", parent = tbl)     # sibling -> auto-closes Batch 1/2
  log_info("rows 501-900")
  log_close(load)                         # cascade: Batch 2/2 + Table + Load

  log_close(run)                          # close the manual root
})

# --- Run 2: a fatal error stops the run ------------------------------------

logtree_reset()
with_logging(deploy())
