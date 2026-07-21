# group_by: every situation, one section each. Each scenario resets state and
# runs in its own frame so steps close cleanly on return.
#
#   source("debug/04_group_situations.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, fn) {
  section(title)
  logtree_reset()
  tryCatch(with_logging(fn(), summary = FALSE),
           error = function(e) cat("(script continued after error: ", conditionMessage(e), ")\n", sep = ""))
}

# ---------------------------------------------------------------------------
# A. Adjacent steps sharing a value collapse under ONE header (the core case).
#    Each check() opens+closes its own step; both share value "x" -> reused.
run_section("A. adjacent same value -> one header", function() {
  check <- function(val, name) log_step(name, group_by = c(batch = val))
  log_step("Root A")
  check("x", "step 1")
  check("x", "step 2")
})

# ---------------------------------------------------------------------------
# B. Value changes every iteration -> a header per iteration (single member).
run_section("B. value changes each iteration -> header per item", function() {
  proc <- function(i) log_step(paste0("item ", i), group_by = c(iter = i))
  log_step("Root B")
  for (i in 1:3) proc(i)
})

# ---------------------------------------------------------------------------
# C. Mockup style: embed the value in the name (setNames) to show < Item N >.
#    Two steps per item, both under the same < Item i > header.
run_section("C. value-in-name header < Item N > wrapping several steps", function() {
  step <- function(i, name) log_step(name, group_by = stats::setNames(i, paste0("Item ", i)))
  log_step("Root C")
  for (i in 1:2) { step(i, "validate"); step(i, "save") }
})

# ---------------------------------------------------------------------------
# D. Adjacency, NOT global: a value that recurs non-adjacently gets a NEW group
#    (a..b..a -> three headers, the two "a" groups are never merged).
run_section("D. non-adjacent same value -> separate groups", function() {
  step <- function(v, name) log_step(name, group_by = c(k = v))
  log_step("Root D")
  step("a", "a1")
  step("b", "b1")   # value change closes group "a"
  step("a", "a2")   # "a" again, but non-adjacent -> fresh group
})

# ---------------------------------------------------------------------------
# E. A plain (ungrouped) step after a group is a SIBLING of the group: the
#    lingering group closes first, so "plain" is not nested inside it.
run_section("E. plain step after a group -> sibling, group closes", function() {
  g <- function() log_step("grouped", group_by = c(k = 1))
  p <- function() log_step("plain")
  log_step("Root E")
  g()
  p()
})

# ---------------------------------------------------------------------------
# F. A leaf logged at the group's level also closes the lingering group, so the
#    leaf renders under the parent, not inside the (finished) group.
run_section("F. leaf after a group closes the group", function() {
  g <- function() log_step("grouped", group_by = c(k = 1))
  log_step("Root F")
  g()
  log_success("after the group")
})

# ---------------------------------------------------------------------------
# G. Nested groups: a grouped step's frame opens its own grouped sub-steps.
#    < run > wraps each "outer i"; inside it < phase > groups the checks by
#    category (io, io -> one group; cpu -> another).
run_section("G. nested groups (group inside a grouped member)", function() {
  outer <- function(i) {
    log_step(paste0("outer ", i), group_by = c(run = i))
    chk <- function(name, cat) log_step(name, group_by = c(phase = cat))
    chk("load", "io"); chk("read", "io"); chk("calc", "cpu")
  }
  log_step("Root G")
  for (i in 1:2) outer(i)
})

# ---------------------------------------------------------------------------
# H. Unnamed group_by -> the header name falls back to as.character(value).
run_section("H. unnamed group_by -> name = value", function() {
  step <- function(v) log_step(paste0("do ", v), group_by = v)
  log_step("Root H")
  step("alpha"); step("alpha"); step("beta")
})

# ---------------------------------------------------------------------------
# I. Status elevation inside a grouped member: all three tasks share value 1
#    (one group, three members); task 2 logs a warning so its Done glyph
#    elevates. The group header itself carries no status.
run_section("I. warning elevation inside a grouped member", function() {
  step <- function(i) {
    log_step(paste0("task ", i), group_by = c(run = 1))
    log_info("working")
    if (i == 2) log_warn("slow response")
  }
  log_step("Root I")
  for (i in 1:3) step(i)
})

# ---------------------------------------------------------------------------
# J. An error thrown inside a grouped step: with_logging() flags open steps as
#    failed, logs the error, and the group is cascade-closed silently (no
#    stray "Done" line) as the stack unwinds. Then rethrown.
run_section("J. error thrown inside a grouped step (with_logging)", function() {
  step <- function(i) {
    log_step(paste0("job ", i), group_by = c(run = 1))
    if (i == 2) stop("boom at job 2")
    log_success("ok")
  }
  log_step("Root J")
  for (i in 1:3) step(i)
})

# ---------------------------------------------------------------------------
# K. group_by must be length-1 (named vector). Longer input errors early.
section("K. invalid group_by (length > 1) errors")
logtree_reset()
tryCatch(
  (function() log_step("x", group_by = c(a = 1, b = 2)))(),
  error = function(e) cat("caught: ", conditionMessage(e), "\n", sep = "")
)

cat("\n")
