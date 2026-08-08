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
register_sink <- function(fn, threshold = NULL, trace = FALSE, store = NULL) {
  if (!is.function(fn)) {
    stop("`fn` must be a function taking one argument (the event).", call. = FALSE)
  }
  id <- new_sink_id()
  the$sinks[[id]] <- list(fn = fn, threshold = resolve_threshold(threshold))
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
#' @param threshold Minimum leaf level this sink receives: one of `"debug"`,
#'   `"info"`, `"warn"`, `"error"`. `NULL` (the default) follows the global
#'   [logtree_threshold()], read afresh for each event. Step open/close lines are
#'   never gated, whatever the threshold.
#' @return The sink's id, invisibly -- pass it to [logtree_sink_remove()].
#' @seealso [logtree_sinks()], [logtree_sink_remove()], [logtree_sink_file()],
#'   [logtree_sink_memory()]
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
#'
#' # A sink that only ever hears about failures.
#' h <- logtree_sink(function(event) invisible(NULL), threshold = "error")
#' logtree_sink_remove(h)
logtree_sink <- function(fn, threshold = NULL) {
  invisible(register_sink(fn, threshold = threshold))
}

#' Collect logged events in memory
#'
#' Registers a sink that keeps every event in a buffer instead of writing it
#' anywhere, so a run's logging can be *asserted on* rather than eyeballed.
#' Read the buffer back with [logtree_sink_memory_events()]. This is the
#' answer to "did my pipeline log what it should have?" -- previously that meant
#' capturing console output and pattern-matching the rendered tree.
#'
#' The buffer is dropped when the sink is removed with [logtree_sink_remove()],
#' and it is capped: a long-running process cannot grow it without bound.
#'
#' @param max Maximum number of events to keep. Once the buffer is full the
#'   oldest events are dropped, so what you read back is always the most recent
#'   `max`. Default `1000`.
#' @param threshold Minimum leaf level to collect, as in [logtree_sink()].
#'   `NULL` (the default) follows the global [logtree_threshold()]; pass
#'   `"debug"` to collect everything a run logged regardless of what the console
#'   was set to show.
#' @return The sink's id, invisibly -- pass it to
#'   [logtree_sink_memory_events()] to read the buffer, and to
#'   [logtree_sink_remove()] to stop collecting.
#' @seealso [logtree_sink_memory_events()], [logtree_sink()]
#' @export
#' @examples
#' logtree_reset()
#' h <- logtree_sink_memory()
#'
#' f <- function() {
#'   log_step("Load data")
#'   log_warn("coerced 3 rows")
#' }
#' invisible(f())
#'
#' events <- logtree_sink_memory_events(h)
#' events[, c("level", "label", "status")]
#'
#' logtree_sink_remove(h)
logtree_sink_memory <- function(max = 1000, threshold = NULL) {
  if (!is.numeric(max) || length(max) != 1L || is.na(max) || max < 1) {
    stop("`max` must be a single positive number of events.", call. = FALSE)
  }
  max <- as.integer(max)
  # An environment, not a list in a closure variable: the buffer has to be
  # readable from outside the sink function, and it is parked in
  # `the$sink_stores` so it is dropped with the sink rather than kept alive by
  # the closure alone.
  store <- new.env(parent = emptyenv())
  store$events <- list()
  fn <- function(event) {
    store$events[[length(store$events) + 1L]] <- event_record(event)
    n <- length(store$events)
    if (n > max) store$events <- store$events[seq.int(n - max + 1L, n)]
    invisible(NULL)
  }
  invisible(register_sink(fn, threshold = threshold, store = store))
}

#' Read a memory sink's collected events
#'
#' Returns everything a [logtree_sink_memory()] sink has collected so far, as a
#' data frame with one row per event and the same columns a `"json"` file sink
#' writes (see [logtree_sink_file()]), so the two views of a run agree:
#'
#' | Column | What it holds |
#' | ------ | ------------- |
#' | `ts` | when the event was emitted (`POSIXct`) |
#' | `level` | event kind: `"open"`, `"close"`, `"group"`, `"group_close"`, `"leaf"` |
#' | `id`, `parent_id`, `depth` | the node's identity and place in the tree |
#' | `label` | a step's label, a group's name, or a leaf's message |
#' | `elapsed` | seconds, on close lines only; `NA` elsewhere |
#' | `status` | a leaf's status, `"step"`/`"group"` on an opening line, or the resolved status on a close |
#' | `fn`, `file`, `line` | the call site, when the `trace` theme slot recorded one; `NA` otherwise |
#'
#' @param id A memory sink's id, as returned by [logtree_sink_memory()].
#' @return A data frame with one row per collected event, oldest first, and zero
#'   rows (with the columns above) when nothing has been logged yet.
#' @seealso [logtree_sink_memory()]
#' @export
#' @examples
#' logtree_reset()
#' h <- logtree_sink_memory()
#' f <- function() log_info("Reading config.yml")
#' invisible(f())
#' logtree_sink_memory_events(h)
#' logtree_sink_remove(h)
logtree_sink_memory_events <- function(id) {
  if (!is.character(id) || length(id) != 1L || is.na(id)) {
    stop("`id` must be a single memory sink id.", call. = FALSE)
  }
  store <- the$sink_stores[[id]]
  if (is.null(store)) {
    stop(sprintf("`%s` is not a registered memory sink.", id), call. = FALSE)
  }
  records_to_df(store$events)
}

# Bind a list of event records into a data frame, column by column, from
# record_proto()'s declared types (R/appenders.R). Typed columns matter: an
# all-missing `elapsed` has to stay numeric rather than collapsing to logical
# NA, or a caller's arithmetic breaks on the one run where nothing closed.
records_to_df <- function(records) {
  proto <- record_proto()
  cols  <- lapply(names(proto), function(nm) {
    empty <- proto[[nm]]
    if (length(records) == 0L) return(empty)
    na <- empty[NA_integer_]
    do.call(c, lapply(records, function(r) {
      v <- r[[nm]]
      if (is.null(v) || length(v) != 1L || is.na(v)) na else v
    }))
  })
  names(cols) <- names(proto)
  as.data.frame(cols, stringsAsFactors = FALSE)
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
