devtools::load_all()

# Mixed logging, deep tree.
#
# Three mechanisms in one run:
#   * with_logging()          -- top-level wrapper: error handling + run summary
#   * log_step()              -- auto steps inside functions, self-close on
#                                frame exit; nesting follows the call stack
#   * log_open() / log_close()-- manual steps for structure the call stack does
#                                not give you (a block-level root, explicit
#                                parent links, hand-controlled batches)
#
# Note: an auto log_step() written directly in the with_logging({ ... }) block
# would bind its close to the *script's* frame (never fires here), so the
# block-level scaffolding is built manually; the auto steps live inside the
# functions the block calls.

logtree_reset()

# --- Auto steps: depth comes from the call stack --------------------------

validate_file <- function(path) {
  log_step(paste("Validate", path))   # child of whoever called us
  log_info("checksum ok")
  log_success("schema ok")            # leaves render one level deeper
}

read_source <- function() {
  log_step("Read source")
  for (f in c("a.csv", "b.csv")) validate_file(f)  # deeper still
  log_info("2 files read")
}

transform_data <- function() {
  log_step("Transform")
  log_step("Normalize units")   # same frame -> nests under Transform
  log_warn("3 rows coerced")    # elevates the enclosing step to a warning
  log_info("units normalized")
}

# --- The run --------------------------------------------------------------


  run <- log_open("ETL run")          # manual root (level 1)

  read_source()                       # ETL run > Read source > Validate > leaf
  transform_data()                    # ETL run > Transform > Normalize > leaf

  # Manual deep branch, hand-linked and hand-closed.
  load <- log_open("Load", parent = run)  # sibling of the two above, under run
  tbl  <- log_open("Table: facts")        # under Load
  log_info("open connection")
  log_open("Batch 1/2")                   # under Table
  log_info("rows 1-500")
  log_open("Batch 2/2", parent = tbl)     # sibling -> auto-closes Batch 1/2
  log_info("rows 501-900")
  log_close(load)                         # cascade: Batch 2/2 + Table + Load

  log_close(run)                          # close the manual root

