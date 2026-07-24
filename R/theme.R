glyph_keys <- c("step", "debug", "info", "success", "warning", "error", "interrupted")

theme_preset <- function(name) {
  switch(name,
    unicode = glyphs_unicode,
    ascii   = glyphs_ascii,
    emoji   = glyphs_emoji,
    stop("Unknown theme preset: ", name, call. = FALSE)
  )
}

# Resolve the `compact` argument of logtree_theme() to NULL / "medium" / "tight".
resolve_compact <- function(x) {
  if (is.null(x) || isFALSE(x)) return(NULL)
  if (isTRUE(x)) return("tight")
  match.arg(x, c("medium", "tight"))
}

# Mutate the active theme in place for a compact density. "medium" drops the
# trailing gap after each connector (col_gap 0); "tight" also slims the
# branch/corner connectors to a single character. Cleared by a later preset
# swap, since a fresh preset has no col_gap and full-width connectors.
apply_compact <- function(level) {
  the$theme$col_gap <- 0L
  if (identical(level, "tight")) {
    for (key in c("branch", "corner")) {
      the$theme[[key]]$glyph <- substring(the$theme[[key]]$glyph, 1L, 1L)
    }
  }
  invisible(NULL)
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
#' @param compact Density of the tree's per-level indentation. `FALSE` (the
#'   default) keeps the normal spacing (three columns per level in the unicode
#'   theme); `"medium"` drops the trailing gap after each connector (two columns
#'   per level); `"tight"` additionally slims the branch and corner connectors
#'   to a single character (one column per level). `TRUE` is an alias for
#'   `"tight"`. Compact applies to the active (console) theme and is cleared by a
#'   subsequent preset swap such as `logtree_theme("unicode")`.
#' @return `NULL`, invisibly.
#' @details
#' An override list is keyed by *slot*; each slot's value is itself a named
#' list of *fields*. Only the fields you name are changed -- everything else is
#' kept from the active theme.
#'
#' **Slots** (valid names in an override / preset list):
#'
#' | Slot | Applies to | Fields it accepts |
#' | ---- | ---------- | ----------------- |
#' | `step` | open / running step glyph | `glyph`, `width`, `color` |
#' | `info` | `log_info()` leaf | `glyph`, `width`, `color` |
#' | `debug` | `log_debug()` leaf | `glyph`, `width`, `color` |
#' | `success` | success glyph (clean close, `log_success()`) | `glyph`, `width`, `color` |
#' | `warning` | `log_warn()` / elevated step glyph | `glyph`, `width`, `color` |
#' | `error` | `log_error()` / elevated step glyph | `glyph`, `width`, `color` |
#' | `interrupted` | abnormal-exit (dimmed) glyph | `glyph`, `width`, `color` |
#' | `group` | group header marker | `glyph`, `color`, `bracket` |
#' | `branch` | child connector (`├─`) | `glyph`, `color` |
#' | `corner` | close-line connector (`└─`) | `glyph`, `color` |
#' | `pipe` | vertical rail (`│`) | `glyph`, `color` |
#'
#' **Fields** (valid names inside a slot):
#'
#' | Field | Type | Accepted values |
#' | ----- | ---- | --------------- |
#' | `glyph` | `character(1)` | Any string, including `""`. In package source, non-ASCII must be written as `\u`/`\U` escapes, never literal characters. |
#' | `width` | `integer(1)` | Rendered display width of `glyph` (`1` for normal, `2` for emoji / wide cells). Drives column alignment and cannot be measured, so set it to the true width. Status slots only (`step`, `info`, `debug`, `success`, `warning`, `error`, `interrupted`). |
#' | `color` | `character` or `NULL` | One or more cli styles, or `NULL` for no styling. Named colors (`"red"`, `"cyan"`, `"silver"`, ...), bright variants (`"br_red"`), backgrounds (`"bg_blue"`), text styles (`"bold"`, `"italic"`, `"dim"`), or a hex string (`"#ff8800"`). A character vector combines styles, e.g. `c("red", "bold")`. See [cli::combine_ansi_styles()]. |
#' | `bracket` | `logical(1)` | `group` slot only. `TRUE` wraps the header name in `< >`; default `FALSE`. |
#' @export
#' @examples
#' logtree_theme("ascii")
#' logtree_theme("unicode")
#' logtree_theme(overrides = list(success = list(glyph = "*")))
#' logtree_theme(overrides = list(group = list(glyph = "#", bracket = TRUE)))
#' logtree_theme("unicode", compact = "medium")
#' logtree_theme("unicode", compact = "tight")
#' logtree_theme("unicode")
logtree_theme <- function(theme = c("unicode", "ascii", "emoji"), overrides = list(),
                          compact = FALSE) {
  if (is.character(theme)) {
    theme <- match.arg(theme)
    the$theme <- theme_preset(theme)
  } else if (is.list(theme)) {
    # Called as logtree_theme(list(...)) -- overrides-only, merge onto
    # whatever theme is already active.
    overrides <- theme
  } else {
    stop("`theme` must be a preset name or a list of overrides.", call. = FALSE)
  }

  # Apply the compact density before user overrides so explicit overrides win.
  compact <- resolve_compact(compact)
  if (!is.null(compact)) apply_compact(compact)

  for (key in names(overrides)) {
    the$theme[[key]] <- utils::modifyList(the$theme[[key]], overrides[[key]])
  }

  invisible(NULL)
}

#' Set the minimum log level threshold to render
#'
#' Leaf lines below this level are silently skipped: `log_debug()` counts as
#' `"debug"`, `log_info()` and `log_success()` count as `"info"`, `log_warn()`
#' as `"warn"`, `log_error()` as `"error"`. Step open/close lines always
#' render regardless of verbosity, since hiding them would break the tree
#' structure. Suppressed `log_warn()`/`log_error()` calls still elevate the
#' enclosing step's close glyph -- verbosity only hides the leaf line's own text.
#'
#' @param level One of `"debug"`, `"info"`, `"warn"`, `"error"` (case-insensitive).
#' @return `NULL`, invisibly.
#' @export
#' @examples
#' logtree_threshold("info")
logtree_threshold <- function(level = c("debug", "info", "warn", "error")) {
  the$verbosity <- match.arg(tolower(level), c("debug", "info", "warn", "error"))
  invisible(NULL)
}

theme_slot_width <- function(theme = the$theme) {
  max(vapply(theme[glyph_keys], function(g) g$width, integer(1)))
}

# Trailing-space columns after each connector/rail. Defaults to 1L when the
# theme carries no `col_gap` (every built-in preset), so non-compact rendering
# is byte-for-byte unchanged; compact mode sets it to 0L.
theme_col_gap <- function(theme = the$theme) {
  if (is.null(theme$col_gap)) 1L else theme$col_gap
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
