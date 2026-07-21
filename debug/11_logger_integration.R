# Bridging the `logger` package (daroczig/logger) into logtree: a custom
# *layout* (logtree::layout_logtree) paired with logger's built-in no-op
# appender (logger::appender_void), so logtree does the real rendering as a
# layout side effect. Requires the `logger` package (Suggests only).
#
#   source("debug/11_logger_integration.R")
devtools::load_all()

if (!requireNamespace("logger", quietly = TRUE)) {
  stop("This demo needs the 'logger' package: install.packages('logger')")
}

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

logtree_reset()
logtree_set_theme("unicode")
logtree_set_verbosity("debug")

ns <- "logtree_demo"
logger::log_layout(logtree::layout_logtree, namespace = ns)
logger::log_appender(logger::appender_void, namespace = ns)

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

# Reset this namespace back to logger's own defaults so the demo doesn't
# leak into the rest of the R session.
logger::log_layout(logger::layout_simple, namespace = ns)
logger::log_appender(logger::appender_console, namespace = ns)
