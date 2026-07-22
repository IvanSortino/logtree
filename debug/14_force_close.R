devtools::load_all()

# Force-close a section inline with `close = TRUE`.
#
# Every `log_*` leaf (and `log_open()`/`log_step()`) takes `close = TRUE`. It
# force-closes the enclosing section without printing a "Done" line: the log
# line itself becomes the section's terminal (corner) line. This is the live
# streaming logger's one chance to know a line is the last sibling, so the
# corner connector is used instead of the branch.

logtree_reset()

# 1. A leaf that closes its section. The warn line takes the corner connector
#    (no separate "Done  <elapsed>" line follows).
log_open("Step 2")
log_warn("child warn 1", close = TRUE)

# 2. The section is genuinely popped: the next sibling opens at the outer
#    depth, exactly as if log_close() had been called.
log_open("Step 3")
log_info("Loaded 3 records")
log_success("all good", close = TRUE)   # closes Step 3 with a success corner

# 3. `close = TRUE` on log_open()/log_step() is a header-only marker: it prints
#    the opening line, then closes silently -- no children, no "Done" line.
log_open("--- phase two ---", close = TRUE)

f <- function() {
  # log_step(close = TRUE) skips its usual close-on-frame-exit too.
  log_step("checkpoint", close = TRUE)
  log_info("work continues at the outer level")
}
f()

# 4. Silent close still folds status up into a group: the member that warned
#    colours the group's eventual close line, even though its own "Done" line
#    was suppressed.
g <- function() {
  log_step("record 1", group_by = c(Batch = "nightly"))
  log_warn("checksum mismatch", close = TRUE)
  log_step("record 2", group_by = c(Batch = "nightly"))
}
g()
log_open("done batching")   # ungrouped sibling settles the group above
