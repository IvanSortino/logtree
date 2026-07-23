# Bridging the `logger` package (daroczig/logger) into logtree in one call:
# logtree_logger() registers logtree's layout + logger's no-op appender and
# opens logger's own threshold, so every logger::log_*() call renders as a
# logtree leaf. Requires the `logger` package (Suggests only).
#
#   source("debug/09_logger_integration.R")
devtools::load_all()

if (!requireNamespace("logger", quietly = TRUE)) {
  stop("This demo needs the 'logger' package: install.packages('logger')")
}

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

logtree_reset()
logtree_theme("unicode")
logtree_threshold("debug")

# One call wires logger -> logtree for this namespace. It is persistent for
# the session (like logger's own config) -- there is no automatic teardown.
ns <- "logtree_demo"
logtree_logger(namespace = ns)

section("logger calls rendered as logtree leaves")
pipeline <- function() {
  log_step("Pipeline")
  logger::log_info("connecting to API", namespace = ns)
  logger::log_success("connected", namespace = ns)
  logger::log_warn("rate limit at 80 percent", namespace = ns)
  request_id <- "9f3a"
  logger::log_debug("request id = {request_id}", namespace = ns)
  logger::log_error("request failed after 3 retries", namespace = ns)
}
with_logging(pipeline(), summary = FALSE)
