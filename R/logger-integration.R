#' A `logger` layout that renders through logtree
#'
#' Bridges the `logger` package (<https://daroczig.github.io/logger/>) into
#' `logtree`'s tree rendering. `logger`'s own per-call pipeline is
#' `formatter() -> layout() -> appender()`: only the *layout* stage receives
#' the structured `level` object (an integer with a `"level"` attribute
#' such as `"INFO"`) -- `appender()` only ever sees a pre-formatted
#' character line -- so a custom layout, not a custom appender, is the
#' correct integration point. Register it as `logger`'s layout and pair it
#' with `logger::appender_void` (a ready-made no-op) so that `logtree`'s
#' rendering, which happens as a side effect of the layout call, is the
#' only visible output:
#'
#' ```r
#' logger::log_layout(logtree::layout_logtree)
#' logger::log_appender(logger::appender_void)
#' ```
#'
#' `logger` severities map onto `logtree` leaf levels as: `FATAL`/`ERROR` ->
#' [log_error()], `WARN` -> [log_warn()], `SUCCESS` -> [log_success()],
#' `INFO` -> [log_info()], `DEBUG`/`TRACE` -> [log_debug()] (`logger` has
#' two debug-ish tiers, `logtree` has one, so both collapse to the same
#' leaf). Note `logger`'s own `log_threshold()` already gates before the
#' layout is ever invoked; `logtree_threshold()` is then an
#' independent, second gate applied on top of that -- both legitimately
#' apply at once, this is not a bug.
#'
#' @param level A `logger` log level object (e.g. `logger::INFO`), as
#'   passed in by `logger`'s internal dispatch.
#' @param msg Character scalar, already formatted by `logger`'s formatter
#'   stage (glue interpolation has already happened by this point).
#' @param namespace,.logcall,.topcall,.topenv,.timestamp Unused; accepted
#'   only because `logger`'s dispatcher calls every layout with this exact
#'   signature (see `logger::layout_simple`).
#' @return `character(0)`, invisibly. The record is discarded by
#'   `logger::appender_void()` regardless, so its content is irrelevant;
#'   a zero-length character vector matches `logger`'s layout contract.
#' @export
#' @examples
#' if (requireNamespace("logger", quietly = TRUE)) {
#'   logtree_reset()
#'   logger::log_layout(layout_logtree, namespace = "logtree_demo")
#'   logger::log_appender(logger::appender_void, namespace = "logtree_demo")
#'   log_step("Demo step")
#'   logger::log_info("hello", namespace = "logtree_demo")
#' }
layout_logtree <- function(level, msg,
                            namespace  = NA_character_,
                            .logcall   = sys.call(),
                            .topcall   = sys.call(-1),
                            .topenv    = parent.frame(),
                            .timestamp = Sys.time()) {
  leaf_fn <- switch(attr(level, "level"),
    FATAL   = log_error,
    ERROR   = log_error,
    WARN    = log_warn,
    SUCCESS = log_success,
    INFO    = log_info,
    DEBUG   = log_debug,
    TRACE   = log_debug,
    log_info  # unrecognized/future level: degrade rather than crash the caller
  )
  leaf_fn(msg)
  invisible(character(0))
}

#' Route the `logger` package through logtree
#'
#' Call once near the top of a script to make the `logger` package
#' (<https://daroczig.github.io/logger/>) render through `logtree`. It
#' registers [layout_logtree()] as `logger`'s layout and
#' `logger::appender_void` as its appender for `namespace`, so from then on
#' every `logger::log_info()` / `log_warn()` / ... call in that namespace
#' prints as a `logtree` leaf. This is the one-call form of the manual
#' `logger::log_layout()` + `logger::log_appender()` pairing.
#'
#' With `threshold = TRUE` (the default) it also opens `logger`'s own
#' threshold to `TRACE` for the namespace. `logger` gates on its threshold
#' *before* the layout runs, so without this a `logger::log_debug()` would
#' never reach `logtree`; opening it makes [logtree_threshold()] the single
#' effective gate.
#'
#' Bridge only: it does not install error handling. Wrap the run body in
#' [with_logging()] as well when you want failed-run elevation and a summary
#' line. The change is persistent for the session (matching `logger`'s own
#' global configuration style); there is no automatic teardown.
#'
#' @param namespace `logger` namespace to route. Default `"global"`, the
#'   namespace a bare `logger::log_info("x")` uses.
#' @param threshold Open `logger`'s threshold to `TRACE` for `namespace` so
#'   [logtree_threshold()] is the only gate? Default `TRUE`.
#' @return `NULL`, invisibly.
#' @seealso [layout_logtree()] for the underlying layout, [with_logging()]
#'   for top-level error handling.
#' @export
#' @examples
#' if (requireNamespace("logger", quietly = TRUE)) {
#'   logtree_reset()
#'   logtree_logger(namespace = "logtree_demo")
#'   log_step("Demo step")
#'   logger::log_info("hello", namespace = "logtree_demo")
#' }
logtree_logger <- function(namespace = "global", threshold = TRUE) {
  rlang::check_installed("logger")
  logger::log_layout(layout_logtree, namespace = namespace)
  logger::log_appender(logger::appender_void, namespace = namespace)
  if (threshold) {
    logger::log_threshold(logger::TRACE, namespace = namespace)
  }
  invisible(NULL)
}
