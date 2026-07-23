#
# Demo: with_logging(global = TRUE) -- top-level (script) error handling.
# The block form with_logging({ ... }) wraps a function body. At the top level
# of a *script* there is no body to wrap: with_logging(global = TRUE) instead
# installs a session-persistent global error handler. When an error reaches the
# top level UNHANDLED while logtree steps are open, it marks those steps failed
# and logs the error message as a leaf -- the same clean tree the block form
# produces -- before R prints the error and exits.
#
# This script is MEANT to end with an uncaught error (non-zero exit): that is
# exactly the situation the handler exists for. Run it with:
#   Rscript -e 'devtools::load_all(); source("debug/12_with_logging_global.R")'

devtools::load_all()
logtree_reset()

# Install the handler as the first line of the script.
with_logging(global = TRUE)

# At top level use log_open()/log_close() -- log_step() has no function frame to
# hang its auto-close on.
log_open("Load data")
log_info("reading records.csv")
log_open("Parse rows")
log_warn("coerced 3 rows")

# An uncaught error from here reaches the top level: the global handler fires,
# marks "Parse rows" and "Load data" failed, logs "unexpected EOF" as a leaf,
# and prints "Run failed" -- then the error propagates and the script exits.
stop("unexpected EOF")
