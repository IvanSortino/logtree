#
# Demo: content-key reconcile -- re-running a top-level block does not re-nest.
#
# At top level (the global env) log_open()/log_step() key each step on its
# label plus the call-site source reference. Re-running the same line
# re-anchors to that node instead of nesting under the previous run's
# still-open steps, so depth stays stable however many times you re-run a block
# while iterating -- no logtree_reset() needed between runs.
#
# In Positron/RStudio: select the four log_*() lines below and run them, then
# run them AGAIN -- the tree re-renders at the same depth, it does not get
# deeper. This script reproduces that by evaluating the same parsed block twice.
#
#   Rscript -e 'devtools::load_all(); source("debug/14_srckey_replay.R")'
#

devtools::load_all()
logtree_reset()

max_depth <- function() {
  if (length(logtree:::the$stack) == 0L) return(0L)
  max(vapply(logtree:::the$stack, function(e) e$depth, integer(1)))
}

# The block you would iterate on, parsed WITH source references (the way an IDE
# sends code to the console). At the real console you would just type these.
block <- parse(
  text = paste(
    'log_open("Load data")',
    'log_info("reading records.csv")',
    'log_open("Parse rows")',
    'log_warn("coerced 3 rows")',
    sep = "\n"
  ),
  keep.source = TRUE
)

message("\n--- first run ---")
eval(block, envir = globalenv())
message("max depth after run 1: ", max_depth())

message("\n--- re-run the SAME block (no reset in between) ---")
eval(block, envir = globalenv())
message(
  "max depth after run 2: ", max_depth(),
  "  <- unchanged: the re-run re-anchored instead of nesting"
)

# Escape hatch: two steps that share a label AND are open at the same time
# collapse under the label key -- pass an explicit `key` to keep them distinct.
message("\n--- explicit key= keeps same-label siblings distinct ---")
logtree_reset()
log_open("Batch", key = "batch-1")
log_open("Batch", key = "batch-2")
log_open("Batch")
log_open("Batch")
message("open steps: ", length(logtree:::the$stack), " (both 'Batch', not collapsed)")

logtree_reset()

