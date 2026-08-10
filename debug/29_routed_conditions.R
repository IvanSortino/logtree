# Routing R's own conditions into the tree: with_logging(warnings = ).
#
#   FALSE (default) -- warning() and message() are left exactly as they are
#   TRUE            -- both are routed into the tree as leaf lines
#   "warning" / "message" -- route only that kind
#
# Tier-2 handling caught `error` only. A warning() raised by wrapped code went
# to stderr, outside the tree, while a log_warn() call rendered inside it: the
# same severity in two different places, and no way to read the run as one
# thing afterwards. A routed warning() becomes a log_warn() leaf and a
# message() becomes a log_info() leaf, in place.
#
# It is opt-in, and it has to be, because routing means MUFFLING: a routed
# warning stops at the leaf. It does not reach warnings(), the caller's own
# handlers, or stderr. That is the point -- one record of a run rather than two
# halves -- but it is not a decision to make for somebody without asking, which
# is why the default is FALSE. Section C shows exactly what is given up.
#
#   Rscript -e 'devtools::load_all(); source("debug/29_routed_conditions.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

# The fixture raises R's own conditions rather than logtree's, from inside
# nested functions, the way third-party code would.
pipeline <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  load_data()
  summarise()
}
load_data <- function() {
  log_step("Load data")
  message("using cached manifest")
  log_info("1200 rows")
  warning("3 rows coerced to NA")
}
summarise <- function() {
  log_step("Summarise")
  log_success("3 metrics")
}

# --- A. the default ----------------------------------------------------------
# The warning lands after the run, out of order and out of the tree; the message
# lands mid-tree but on stderr, unindented and unconnected. Both are visible
# here only because this script prints stderr too -- in a captured log they may
# well be somewhere else entirely.
section("A. warnings = FALSE -- R's conditions go their own way")
logtree_reset()
withCallingHandlers(
  with_logging(pipeline(), summary = FALSE),
  warning = function(w) {
    cat("[stderr] Warning:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  },
  message = function(m) {
    cat("[stderr]", conditionMessage(m))
    invokeRestart("muffleMessage")
  }
)

# --- B. routed ---------------------------------------------------------------
section("B. warnings = TRUE -- they become leaves, in place")
logtree_reset()
# Unrouted, for contrast. suppressWarnings() only so the deferred warning does
# not resurface at the end of this script, long after the tree it belongs to.
suppressWarnings(with_logging(pipeline(), summary = FALSE))
cat("\n-- and with routing on --\n")
logtree_reset()
with_logging(pipeline(), summary = FALSE, warnings = TRUE)

# Two things to notice in the routed tree:
#
#   * the message and the warning appear where they happened, at the right
#     depth, between the log lines around them
#   * "Load data" now closes with the warning glyph. A routed warning elevates
#     its step exactly as log_warn() does -- which is honest, and is also why
#     wrapping noisy third-party code will turn a lot of steps yellow

# --- C. what muffling costs --------------------------------------------------
section("C. a routed warning no longer reaches the caller's own handlers")
noisy <- function() {
  log_step("Noisy")
  warning("first")
  warning("second")
}
# Count the warnings that still make it out to a handler of the caller's own.
escapes <- function(expr) {
  n <- 0L
  withCallingHandlers(expr, warning = function(w) {
    n <<- n + 1L
    invokeRestart("muffleWarning")
  })
  n
}

logtree_reset()
routed <- escapes(with_logging(noisy(), summary = FALSE, warnings = TRUE))
logtree_reset()
plain <- escapes(with_logging(noisy(), summary = FALSE))

cat("\nwarnings escaping a routed run:   ", routed, "\n", sep = "")
cat("warnings escaping an unrouted run: ", plain, "\n", sep = "")

# --- D. one kind at a time ---------------------------------------------------
# The commonest middle ground: route warnings, because they are about the run,
# and leave message() alone, because plenty of packages use it for progress
# chatter you would rather not fold into the tree.
section("D. warnings = \"warning\" -- messages left alone")
logtree_reset()
withCallingHandlers(
  with_logging(pipeline(), summary = FALSE, warnings = "warning"),
  message = function(m) {
    cat("[stderr]", conditionMessage(m))
    invokeRestart("muffleMessage")
  }
)

# --- E. errors are unaffected ------------------------------------------------
# Routing sits alongside the error handling that was always there: an error
# still marks every open step, still logs, and is still rethrown.
section("E. the error handler is untouched by routing")
logtree_reset()
failing <- function() {
  log_step("Pipeline")
  load_data()
  stop("model timeout after 30s")
}
res <- tryCatch(with_logging(failing(), summary = TRUE, warnings = TRUE),
                error = function(e) conditionMessage(e))
cat("\nrethrown to the caller:", res, "\n")

# --- F. the call site --------------------------------------------------------
# A handler logs from its own frame, so a frame walk would name the handler as
# the origin of every routed line. The site comes from conditionCall() instead
# -- the call that actually raised the condition.
#
# Which is R's answer, not logtree's, and the two condition kinds answer
# differently: warning() reports the *enclosing* call (load_data()), while
# message() reports the message() call itself. Worth knowing rather than being
# surprised by.
section("F. a routed condition carries the call site that raised it")
logtree_reset()
logtree_theme("unicode", overrides = list(trace = list(show = TRUE)))
with_logging(pipeline(), summary = FALSE, warnings = TRUE)
logtree_theme("unicode")
logtree_reset()
