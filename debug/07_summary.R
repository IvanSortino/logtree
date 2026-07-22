# The end-of-run summary digest: logtree_summary() reports every warning,
# error, and interrupted step accumulated since the last logtree_reset(), each
# with a breadcrumb path -- so you see "what went wrong" without scrolling the
# whole tree. Every log_*() takes summary = TRUE/FALSE to pin or drop a line.
#
#   source("debug/07_summary.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

# ---------------------------------------------------------------------------
# A. Auto-recording: warnings and errors are captured by default (summary = NA).
#    One failure shows up once, at its deepest point, carrying the message.
section("A. warnings + errors captured automatically")
logtree_reset()
parse_csv <- function() {
  log_step("Parse CSV")
  log_warn("coerced 3 rows to numeric")
  log_error("unexpected EOF at line 402")
}
load_data <- function() {
  log_step("Load data")
  parse_csv()
}
tryCatch(load_data(), error = identity)
logtree_summary()

# ---------------------------------------------------------------------------
# B. No handler needed: a raw stop() leaves interrupted steps, still surfaced
#    from their close lines (deepest one kept, ancestors deduped).
section("B. interrupted steps surface with no with_logging()")
logtree_reset()
inner <- function() { log_step("Inner"); stop("disk full") }
outer <- function() { log_step("Outer"); inner() }
tryCatch(outer(), error = identity)
logtree_summary()

# ---------------------------------------------------------------------------
# C. Pin an ordinary line (summary = TRUE) / drop a noisy one (summary = FALSE).
section("C. explicit opt-in / opt-out")
logtree_reset()
job <- function() {
  log_step("Nightly job")
  log_info("processed 10,000 records", summary = TRUE)   # pinned into digest
  log_warn("cache miss rate 12%", summary = FALSE)        # kept off the digest
}
job()
logtree_summary()

# ---------------------------------------------------------------------------
# D. A clean run reports a single "nothing to report" line.
section("D. clean run")
logtree_reset()
clean <- function() { log_step("All good"); log_success("validated 12 params") }
clean()
logtree_summary()
