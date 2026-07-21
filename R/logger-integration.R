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
