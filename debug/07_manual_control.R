devtools::load_all()

# Manual step control + explicit parent linking.
#
# `log_open()` opens a step with no automatic close; `log_close()` closes it
# (and any still-open descendants). Passing `parent =` a chosen open handle
# attaches a step to that parent instead of the innermost open step, so you
# can build the tree by hand.

logtree_reset()

s1 <- log_open("Parent")
log_info("under the parent")

a <- log_open("Child A")     # innermost open step is s1 -> A nests under Parent
log_info("under A")

# Without `parent =`, this would nest under A (the current innermost). We link
# it to s1 instead, so B is a *sibling* of A under Parent.
b <- log_open("Child B", parent = s1)
log_info("under B")

log_close()                  # no id -> closes nearest open step (B)
log_close()                  # closes A

log_close(s1)                # closes the parent; had descendants been left
                             # open, this would cascade-close them too
