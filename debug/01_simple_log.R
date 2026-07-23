# The simplest logtree: wrap a function body in with_logging(), and every
# log_step() inside auto-opens a node that closes when its frame returns.
# Leaves (log_info / log_success / log_warn / log_error) attach to the nearest
# open step. This is the happy path -- no manual open/close, no groups.
#
#   Rscript -e 'devtools::load_all(); source("debug/01_simple_log.R")'
devtools::load_all()
logtree_reset()

prepare <- function() {
  log_step("Prepare data")
  log_info("loading config")
  log_success("3 sources ready")
}

with_logging(prepare())
