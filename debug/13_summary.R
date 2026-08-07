# The end-of-run summary digest: logtree_summary() reports every warning,
# error, and interrupted step accumulated since the last logtree_reset(), each
# with a breadcrumb path -- so you see "what went wrong" without scrolling the
# whole tree. Every log_*() takes summary = TRUE/FALSE to pin or drop a line.
#
#   source("debug/13_summary.R")
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

# ---------------------------------------------------------------------------
# E. Filter the digest: pass a status, or a vector of statuses, to report only
#    those categories. NULL (the default) reports everything.
section("E. filter: report only selected categories")
logtree_reset()
pipeline <- function() {
  log_step("Extract");   log_warn("2 rows dropped")
  log_step("Transform"); log_error("schema mismatch")
  log_info("42 records staged", summary = TRUE)          # pinned
}
pipeline()
cat("-- errors only --\n")
logtree_summary(filter = "error")
cat("-- warnings + errors --\n")
logtree_summary(filter = c("warning", "error"))
cat("-- everything (default) --\n")
logtree_summary()

# ---------------------------------------------------------------------------
# F. Trim the breadcrumb: depth = N keeps only the N deepest crumb nodes (the
#    message counts as the terminal node). Handy when deep nesting makes the
#    full path noisy and only the innermost context matters.
section("F. depth: trim the breadcrumb to its deepest nodes")
logtree_reset()
nested <- function() {
  log_step("Load data")
  log_step("Parse CSV")
  log_step("Tokenize")
  log_error("unexpected EOF at line 402")
}
tryCatch(nested(), error = identity)
cat("-- depth = 1 (message only) --\n")
logtree_summary(depth = 1)
cat("-- depth = 2 (message + parent) --\n")
logtree_summary(depth = 2)
cat("-- full (default) --\n")
logtree_summary()

# ---------------------------------------------------------------------------
# G. Layout: the digest is divided from the log lines by a blank gap plus a cli
#    rule labelled with the counts. `gap` sets the number of blank lines and
#    `rule` the divider (TRUE / FALSE / a custom title) for one call; both
#    default to the active theme's `summary` slot (see H).
section("G. divider layout: gap + rule")
logtree_reset()
deploy <- function() {
  log_step("Deploy")
  log_warn("stale cache on node 3")
  log_error("health check failed on node 7")
}
deploy()

cat("-- default: one blank line + rule carrying the header --\n")
logtree_summary()

cat("\n-- gap = 3, wider separation --\n")
logtree_summary(gap = 3)

cat("\n-- rule = FALSE: flush plain header, as before --\n")
logtree_summary(gap = 0, rule = FALSE)

cat("\n-- rule = \"Run report\": custom title, header below it --\n")
logtree_summary(rule = "Run report")

# ---------------------------------------------------------------------------
# H. Every knob of the digest's appearance lives in the active theme, so it is
#    set once through logtree_theme() -- the same entry point as the tree's own
#    glyphs and colors. The `summary` slot holds the divider (gap / rule /
#    line), the `crumb` slot the breadcrumb separator and the emphasis that
#    sets the path apart from the message.
section("H. customising the digest through the theme")
logtree_reset()
deploy()

cat("-- default (unicode): bold path, dim separator --\n")
logtree_summary()

cat("\n-- a different separator symbol --\n")
logtree_theme(list(crumb = list(glyph = " / ")))
logtree_summary()

cat("\n-- separator and path styling of your own --\n")
logtree_theme(list(
  crumb = list(glyph = " » ", color = "silver", path_color = c("cyan", "bold"))
))
logtree_summary()

cat("\n-- and the divider, set once instead of per call --\n")
logtree_theme(list(summary = list(gap = 2, rule = "Nightly build")))
logtree_summary()

# A preset swap resets every override, the divider and breadcrumb included.
logtree_theme("unicode")
