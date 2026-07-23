# File sinks: emit() fans every event to the always-on console sink plus any
# file sinks registered with logtree_sink_file(path, format = ). Two formats:
#
#   * "text" -- plain-ASCII rendering of the tree (theme-independent), for
#               logfiles / CI artifacts.
#   * "json" -- one NDJSON object per event, each carrying a stable `id` and
#               `parent_id` pointing at its enclosing node (step, group, or
#               root = 0). The flat stream reconstructs the tree WITHOUT
#               relying on depth -- useful for aggregation / post-hoc or
#               parallel-worker merge.
#
# Both sinks are attached to ONE run below (a single with_logging() writes both
# files); both target tempfile(), never the working directory. Note sinks are
# additive and NOT cleared by logtree_reset(), so register once per session.
#
#   source("debug/04_file_sinks.R")
devtools::load_all()

logtree_reset()
txt  <- tempfile(fileext = ".log")
path <- tempfile(fileext = ".ndjson")
logtree_sink_file(txt,  format = "text")
logtree_sink_file(path, format = "json")

run <- function() {
  check <- function(item, label) {
    log_step(label, group = stats::setNames(item, paste0("Item ", item)))
    log_info("running")
    if (item == 2 && label == "bounds") log_warn("out of range")
  }
  process <- function(item) { check(item, "validate"); check(item, "bounds") }
  log_step("Pipeline")
  for (i in 1:2) process(i)
  log_success("done")
}
with_logging(run(), summary = FALSE)

# --- A. text sink: plain-ASCII tree written to a file -----------------------
cat("\n\033[1m== text sink (format = \"text\") ==\033[0m\n")
cat(readLines(txt), sep = "\n")
cat("\n")

# --- B. json sink: id / parent_id on every event ----------------------------
cat("\n\033[1m== NDJSON events (id / parent_id) ==\033[0m\n")
events <- lapply(readLines(path), function(l) jsonlite::fromJSON(l))
for (e in events) {
  cat(sprintf("  id=%-3s parent=%-3s  %-6s %-8s %s\n",
              e$id, e$parent_id, e$level, e$status, e$label))
}

# --- C. rebuild the tree from parent_id ALONE (ignore depth) ----------------
# Take only the node-opening events (open/group); each knows its parent_id.
cat("\n\033[1m== tree rebuilt from parent_id (depth ignored) ==\033[0m\n")
nodes <- Filter(function(e) e$level %in% c("open", "group"), events)
label_of <- setNames(vapply(nodes, function(e) e$label, ""),
                     vapply(nodes, function(e) as.character(e$id), ""))
parent_of <- setNames(vapply(nodes, function(e) e$parent_id, 0),
                      vapply(nodes, function(e) as.character(e$id), ""))

print_node <- function(id, indent) {
  wrap <- if (any(vapply(nodes, function(e) e$level == "group" && e$id == id, FALSE)))
            c("< ", " >") else c("", "")
  cat(strrep("  ", indent), wrap[1], label_of[[as.character(id)]], wrap[2], "\n", sep = "")
  kids <- names(parent_of)[parent_of == id]
  for (k in kids) print_node(as.integer(k), indent + 1)
}
roots <- names(parent_of)[parent_of == 0]
for (r in roots) print_node(as.integer(r), 0)

cat("\n")
