glyph_keys <- c("step", "info", "success", "warning", "error", "incomplete")

theme_preset <- function(name) {
  switch(name,
    unicode = glyphs_unicode,
    ascii   = glyphs_ascii,
    emoji   = glyphs_emoji,
    stop("Unknown theme preset: ", name, call. = FALSE)
  )
}

#' Set the active glyph/color theme
#'
#' @param theme Either a preset name (`"unicode"`, `"ascii"`, `"emoji"`) to
#'   swap the whole glyph set, or a named list of per-key overrides to merge
#'   onto the currently active theme (matching the two calling styles shown
#'   in the package documentation).
#' @param overrides A named list of per-key overrides applied on top of
#'   `theme` after it is resolved. Each entry may specify `glyph`, `width`,
#'   and/or `color`; unspecified fields are kept from the existing entry. The
#'   `group` slot also accepts `bracket` (logical, default `FALSE`): when
#'   `TRUE` the header name is wrapped in `< >`.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_set_theme("ascii")
#' logtree_set_theme("unicode")
#' logtree_set_theme(overrides = list(success = list(glyph = "*")))
#' logtree_set_theme(overrides = list(group = list(glyph = "#", bracket = TRUE)))
#' logtree_set_theme("unicode")
logtree_set_theme <- function(theme = c("unicode", "ascii", "emoji"), overrides = list()) {
  if (is.character(theme)) {
    theme <- match.arg(theme)
    the$theme <- theme_preset(theme)
  } else if (is.list(theme)) {
    # Called as logtree_set_theme(list(...)) -- overrides-only, merge onto
    # whatever theme is already active.
    overrides <- theme
  } else {
    stop("`theme` must be a preset name or a list of overrides.", call. = FALSE)
  }

  for (key in names(overrides)) {
    the$theme[[key]] <- utils::modifyList(the$theme[[key]], overrides[[key]])
  }

  invisible(NULL)
}

#' Set the minimum verbosity level to render
#'
#' Leaf lines below this level are silently skipped: `log_info()` and
#' `log_success()` count as `"info"`, `log_warn()` as `"warn"`, `log_error()`
#' as `"error"`. Step open/close lines always render regardless of
#' verbosity, since hiding them would break the tree structure. Suppressed
#' `log_warn()`/`log_error()` calls still elevate the enclosing step's
#' close glyph -- verbosity only hides the leaf line's own text.
#'
#' @param level One of `"debug"`, `"info"`, `"warn"`, `"error"`.
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_set_verbosity("info")
logtree_set_verbosity <- function(level = c("debug", "info", "warn", "error")) {
  the$verbosity <- match.arg(level)
  invisible(NULL)
}

theme_slot_width <- function(theme = the$theme) {
  max(vapply(theme[glyph_keys], function(g) g$width, integer(1)))
}

colorize <- function(text, color, enabled = TRUE) {
  if (!enabled || is.null(color)) return(text)
  style <- do.call(cli::combine_ansi_styles, as.list(color))
  style(text)
}

theme_glyph <- function(key, theme = the$theme, color = TRUE) {
  g <- theme[[key]]
  w <- theme_slot_width(theme)
  padded <- paste0(g$glyph, strrep(" ", max(w - g$width, 0L)))
  colorize(padded, g$color, color)
}

theme_connector <- function(key, theme = the$theme, color = TRUE) {
  g <- theme[[key]]
  colorize(g$glyph, g$color, color)
}
