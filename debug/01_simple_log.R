devtools::load_all()

logtree_reset()
log_step("Step 1")
log_info("child info 1")
log_info("child info 2")
log_step("Step 2") # should be level 1, same as Step 1
log_warn("child warn 1")

