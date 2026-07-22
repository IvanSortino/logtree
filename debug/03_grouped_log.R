devtools::load_all()
logtree_reset()

# group demo: adjacent log_step() calls sharing the same value nest under a
# single < name > header. Embed the value in the name (setNames) to show it in
# the header, e.g. < Item 1 >. Here each item runs several checks that all
# collapse under one header.
run_demo <- function() {
  check <- function(item, label) {
    log_step(label, group = stats::setNames(item, paste0("Item ", item)))
    log_info(paste0(label, " running"))
    if (item == 2 && label == "check bounds") log_warn("value out of range")
    log_success(paste0(label, " ok"))
  }
  process_item <- function(item) {
    check(item, "validate schema")
    check(item, "check bounds")
  }
  log_step("Pipeline run")
  log_info("loading data")
  for (i in 1:2) process_item(i)
  log_success("pipeline complete")
}
with_logging(run_demo())
