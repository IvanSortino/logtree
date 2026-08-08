# The sink registry.
#
# Sinks used to be an unnamed, append-only list: there was no way to register
# one of your own, and no way to remove any of them again -- a test that added
# a sink leaked it into every later test in the same session. They are keyed by
# id now, so a registration can be undone.
#
# A *named list* rather than an environment, deliberately: sinks must fire in
# registration order and a named list preserves it, where an environment has no
# order at all. emit() (R/appenders.R) iterates it in name order.
#
# The console sink lives under the reserved id "console" so it can be targeted
# like any other -- turning the console off is a real thing a library author
# wants. logtree_reset() still does not clear sinks: the split is deliberate
# (sinks survive a reset, the summary digest does not), and
# logtree_sink_remove() is the explicit path instead.

console_sink_id <- "console"

new_sink_id <- function() {
  id <- paste0("sink", the$next_sink_id)
  the$next_sink_id <- the$next_sink_id + 1L
  id
}

# Register `fn` under a fresh id, returning that id.
#
# `trace` says whether this sink asked for call-site capture in its own right
# (logtree_sink_file(trace = )), which switches capture on for as long as the
# sink is registered -- see trace_enabled() (R/trace.R). It is tracked as a set
# of ids rather than a count precisely so that removal can take it back again.
#
# `store` is the backing environment of a memory sink, parked here so it is
# dropped along with the sink rather than kept alive by the closure alone.
register_sink <- function(fn, trace = FALSE, store = NULL) {
  if (!is.function(fn)) {
    stop("`fn` must be a function taking one argument (the event).", call. = FALSE)
  }
  id <- new_sink_id()
  the$sinks[[id]] <- list(fn = fn)
  if (isTRUE(trace)) the$trace_sinks <- c(the$trace_sinks, id)
  if (!is.null(store)) the$sink_stores[[id]] <- store
  id
}

#' Register a sink of your own
#'
#' Adds an arbitrary function as an output destination. Every logged event fans
#' out to each registered sink in registration order, so a custom sink runs
#' alongside the console and any file sinks. Use it to push events at a
#' database, a metrics collector, or an in-test collector of your own; for the
#' built-in file destinations see [logtree_sink_file()].
#'
#' `fn` is called with one argument, the event: a list whose `kind` is one of
#' `"open"`, `"close"`, `"group"`, `"group_close"` or `"leaf"`. Step-shaped
#' events (everything but `"leaf"`) carry the step's record under `entry`, while
#' a leaf carries its own fields directly.
#'
#' A sink that throws does not take the rest of the fanout down with it: the
#' error is caught, the remaining sinks still run, and a warning naming the sink
#' is raised once (per sink, until the next [logtree_reset()]). A logger should
#' witness failures, not become a source of them.
#'
#' @param fn A function of one argument, called with each emitted event. Its
#'   return value is ignored.
#' @return The sink's id, invisibly -- pass it to [logtree_sink_remove()].
#' @seealso [logtree_sinks()], [logtree_sink_remove()], [logtree_sink_file()]
#' @export
#' @examples
#' logtree_reset()
#' seen <- character(0)
#' h <- logtree_sink(function(event) seen <<- c(seen, event$kind))
#'
#' f <- function() log_step("Step one")
#' invisible(f())
#' seen
#'
#' logtree_sink_remove(h)
logtree_sink <- function(fn) {
  invisible(register_sink(fn))
}

#' List the registered sinks
#'
#' The ids of every sink currently registered, in the order they fire. The
#' console sink is always first under the reserved id `"console"` unless it has
#' been removed.
#'
#' @return A character vector of sink ids.
#' @seealso [logtree_sink()], [logtree_sink_remove()]
#' @export
#' @examples
#' logtree_sinks()
logtree_sinks <- function() {
  names(the$sinks)
}

#' Remove registered sinks
#'
#' Unregisters one or more sinks by id. Ids that are not registered are ignored,
#' so cleanup code can run unconditionally. The reserved `"console"` id can be
#' removed like any other, which is how a library silences logtree's console
#' output outright.
#'
#' Sinks deliberately survive [logtree_reset()], so this is the only way to take
#' one off again.
#'
#' @param id Character vector of sink ids, as returned by [logtree_sink()],
#'   [logtree_sink_file()] or [logtree_sinks()].
#' @return The removed sink functions, invisibly: a named list keyed by the ids
#'   actually removed (empty when none matched). Re-registering one with
#'   [logtree_sink()] restores it, under a fresh id and therefore at the end of
#'   the firing order.
#' @seealso [logtree_sink()], [logtree_sinks()]
#' @export
#' @examples
#' logtree_reset()
#' h <- logtree_sink(function(event) invisible(NULL))
#' logtree_sinks()
#' logtree_sink_remove(h)
#' logtree_sinks()
logtree_sink_remove <- function(id) {
  if (!is.character(id)) {
    stop("`id` must be a character vector of sink ids.", call. = FALSE)
  }
  known   <- intersect(id, names(the$sinks))
  removed <- lapply(known, function(i) the$sinks[[i]]$fn)
  names(removed) <- known
  for (i in known) {
    the$sinks[[i]]       <- NULL
    the$sink_stores[[i]] <- NULL
  }
  # A sink that wanted call-site capture stops wanting it once it is gone, and a
  # sink that failed takes its "already warned" marker with it.
  the$trace_sinks <- setdiff(the$trace_sinks, known)
  the$sink_failed <- setdiff(the$sink_failed, known)
  invisible(removed)
}
