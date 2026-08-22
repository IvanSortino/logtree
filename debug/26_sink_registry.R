# The sink registry: register a sink of your own, list what is registered,
# and take one off again.
#
#   logtree_sink(fn)          -- register any function of one argument, returns
#                                the sink's id
#   logtree_sinks()           -- the ids currently registered, in firing order
#   logtree_sink_remove(id)   -- unregister; returns the removed functions so a
#                                removal can be undone
#
# Sinks used to be an append-only list with no way to add a custom one and no
# way to remove any: a script that registered a file sink was stuck with it for
# the session. They are keyed by id now. logtree_sink_file() returns its id too,
# so a log file can be closed off the same way.
#
# The console sink lives under the reserved id "console", which means it can be
# removed like any other -- worth knowing, though logtree_mute() (script 30) is
# the better tool when you only want quiet for a while.
#
#   Rscript -e 'devtools::load_all(); source("debug/26_sink_registry.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

# One shared fixture: a small tree with a warning in it, so the events a sink
# sees cover open / leaf / close.
tree <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  load_data()
}
load_data <- function() {
  log_step("Load data")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}

# Put the registry back the way we found it between sections.
solo_console <- function() {
  logtree_sink_remove(setdiff(logtree_sinks(), "console"))
  logtree_reset()
}

# --- A. what is registered ---------------------------------------------------
section("A. logtree_sinks() -- the console is always there to begin with")
solo_console()
print(logtree_sinks())

# --- B. a sink of your own ---------------------------------------------------
# `fn` is handed the raw event. `kind` is one of open / close / group /
# group_close / leaf; a leaf carries its fields directly, everything else
# carries the step's record under `entry`.
section("B. logtree_sink(fn) -- counting events as they fly past")
solo_console()
counts <- c()
h <- logtree_sink(function(event) {
  counts[[event$kind]] <<- (if (is.null(counts[[event$kind]])) 0L else counts[[event$kind]]) + 1L
})
cat("registered as:", h, "\n")
with_logging(tree(), summary = FALSE)
cat("\nevents this sink saw:\n")
print(counts)

# --- C. removal --------------------------------------------------------------
section("C. logtree_sink_remove(id) -- and the sink stops hearing about it")
counts <- c()
logtree_sink_remove(h)
print(logtree_sinks())
logtree_reset()
with_logging(tree(), summary = FALSE)
cat("\nevents after removal:", length(counts), "\n")

# --- D. firing order ---------------------------------------------------------
# Registration order is the firing order, and removing one from the middle does
# not disturb the rest. A sink registered afterwards goes to the end.
section("D. sinks fire in registration order")
solo_console()
order <- character(0)
a <- logtree_sink(function(event) order <<- c(order, "a"))
b <- logtree_sink(function(event) order <<- c(order, "b"))
c_ <- logtree_sink(function(event) order <<- c(order, "c"))
f <- function() log_info("one line")
invisible(f())
cat("order:", paste(order, collapse = " -> "), "\n")

logtree_sink_remove(b)
d <- logtree_sink(function(event) order <<- c(order, "d"))
order <- character(0)
invisible(f())
cat("after removing b and adding d:", paste(order, collapse = " -> "), "\n")

# --- E. a file sink has a handle too -----------------------------------------
section("E. logtree_sink_file() returns an id -- so a log file can be closed")
solo_console()
path <- tempfile(fileext = ".log")
fh <- logtree_sink_file(path, format = "text")
cat("file sink id:", fh, "\n")
g <- function() log_info("this line is recorded")
invisible(g())

logtree_sink_remove(fh)
g2 <- function() log_info("this one is not")
invisible(g2())

cat("\n-- the file --\n")
cat(readLines(path), sep = "\n")
cat("\n")

# --- F. a broken sink is skipped, not fatal ----------------------------------
# The logger is a witness to what went wrong; it must not become a new source
# of failures. A sink that throws is caught, the rest of the fanout still runs,
# and a warning naming it is raised once rather than on every single event.
section("F. a sink that throws does not take the others down with it")
solo_console()
survivors <- 0L
logtree_sink(function(event) stop("this sink is broken"))
logtree_sink(function(event) survivors <<- survivors + 1L)

withCallingHandlers(
  invisible(f()),
  warning = function(w) {
    cat("warning raised:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)
cat("the sink after the broken one still saw", survivors, "event(s)\n")

cat("\n-- and the warning is not repeated on the next event --\n")
withCallingHandlers(
  invisible(f()),
  warning = function(w) {
    cat("warning raised:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)
cat("survivor count now:", survivors, "\n")

# --- G. removing the console -------------------------------------------------
# The reserved "console" id is removable like any other. logtree_sink_remove()
# hands back the functions it removed, so the removal can be undone -- under a
# fresh id, and therefore at the end of the firing order.
section("G. the console sink is removable, and restorable")
solo_console()
saved <- logtree_sink_remove("console")
cat("registered now:", paste(logtree_sinks(), collapse = ", "), "(none)\n")
cat("-- logging with no console sink, nothing should appear between the dashes --\n")
invisible(f())
cat("-- end --\n")

logtree_sink(saved[["console"]])
cat("restored; logging again:\n")
invisible(f())

solo_console()
