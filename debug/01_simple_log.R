devtools::load_all()

# Manual control: open/close steps yourself, so top-level (script/REPL) steps
# become siblings instead of runaway-nesting under the previous one.
logtree_reset()
s1 <- log_open("Step 1")
log_info("child info 1")
log_info("child info 2")
log_close(s1)

log_open("Step 2")   # level 1, sibling of Step 1
log_warn("child warn 1", close = T)
