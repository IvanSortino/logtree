devtools::load_all()

# Manual step control + explicit parent linking.
#
# `log_open()` opens a step with no automatic close; `log_close()` closes it
# (and any still-open descendants). Passing `parent =` a chosen open handle
# attaches a step to that parent. Opening a step beside an already-open
# sibling (same depth) auto-closes that sibling's subtree first -- a new
# sibling means the previous one is done.

logtree_reset()

s1 <- log_open("Parent")
log_info("under the parent")

a <- log_open("Child A")     # innermost open step is s1 -> A nests under Parent
log_info("under A")

# Linked to s1, so B is a sibling of A. A (and any open descendants of it) is
# auto-closed first -- no explicit log_close(a) needed.
b <- log_open("Child B", parent = s1)
log_info("under B")
# log_close()                  # no id -> closes nearest open step (B)

log_close(s1)                # closes the parent
