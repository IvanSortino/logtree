devtools::load_all()

logtree_reset()

run_demo <- function() {
  validate_item <- function(i) {
    log_step(paste0("Validate item ", i))
    log_info("checking schema")
    if (i == 2) log_warn("missing optional field")
    log_success("schema ok")
  }

  process_item <- function(i) {
    log_step(paste0("Process item ", i))
    validate_item(i)
    log_success("processed")
  }

  log_step("Pipeline run")
  log_info("loading data")
  for (i in 1:3) process_item(i)
  log_success("pipeline complete")
}

with_logging(run_demo())
