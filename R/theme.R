glyph_keys <- c("step", "debug", "info", "success", "done", "warning", "error",
                "interrupted")

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
#'   `TRUE` the header name is wrapped in `< >`. The two non-glyph slots
#'   `crumb` and `summary` carry [logtree_summary()]'s appearance -- see the
#'   slot table below.
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
#' | `success` | `log_success()` leaf | `glyph`, `width`, `color` |
#' | `done` | a step's own `Done` line on a clean close | `glyph`, `width`, `color` |
#' | `warning` | `log_warn()` / elevated step glyph | `glyph`, `width`, `color` |
#' | `error` | `log_error()` / elevated step glyph | `glyph`, `width`, `color` |
#' | `interrupted` | abnormal-exit (dimmed) glyph | `glyph`, `width`, `color` |
#' | `group` | group header marker | `glyph`, `color`, `bracket` |
#' | `branch` | child connector: the "tee" drawn before every child line | `glyph`, `color` |
#' | `corner` | close-line connector: the "elbow" drawn on a step's own close line | `glyph`, `color` |
#' | `pipe` | vertical rail carried down the left of nested lines | `glyph`, `color` |
#' | `crumb` | [logtree_summary()] breadcrumb: the separator between path nodes | `glyph`, `color`, `path_color` |
#' | `summary` | [logtree_summary()] divider above the digest | `gap`, `rule`, `line` |
#'
#' `success` and `done` are separate slots that merely *look* the same by
#' default (every preset ships the same tick in both): `success` styles the
#' [log_success()] leaf line, `done` styles the `Done` line a step prints when
#' it closes cleanly. Override one and the other is untouched. A step that
#' closes elevated still renders `warning` / `error` / `interrupted`, so `done`
#' only ever governs the clean close.
#'
#' **Fields** (valid names inside a slot):
#'
#' | Field | Type | Accepted values |
#' | ----- | ---- | --------------- |
#' | `glyph` | `character(1)` | Any string, including `""`. In package source, non-ASCII must be written as `\u`/`\U` escapes, never literal characters. |
#' | `width` | `integer(1)` | Rendered display width of `glyph` (`1` for normal, `2` for emoji / wide cells). Drives column alignment and cannot be measured, so set it to the true width. Status slots only (`step`, `info`, `debug`, `success`, `done`, `warning`, `error`, `interrupted`). |
#' | `color` | `character` or `NULL` | One or more cli styles, or `NULL` for no styling. Named colors (`"red"`, `"cyan"`, `"silver"`, ...), bright variants (`"br_red"`), backgrounds (`"bg_blue"`), text styles (`"bold"`, `"italic"`, `"dim"`), or a hex string (`"#ff8800"`). A character vector combines styles, e.g. `c("red", "bold")`. See [cli::combine_ansi_styles()]. |
#' | `bracket` | `logical(1)` | `group` slot only. `TRUE` wraps the header name in `< >`; default `FALSE`. |
#' | `path_color` | `character` or `NULL` | `crumb` slot only. Styles the breadcrumb's path nodes, setting them apart from a leaf's message (which stays unstyled). Same accepted values as `color`; `"bold"` in the unicode and emoji presets, `NULL` in ascii. |
#' | `gap` | `integer(1)` | `summary` slot only. Blank lines printed above the digest; `0` prints it flush against the tree. |
#' | `rule` | `logical(1)` or `character(1)` | `summary` slot only. `TRUE` draws a [cli::rule()] labelled with the digest header, `FALSE` draws none, a string sets a custom title. |
#' | `line` | `integer(1)` or `character(1)` | `summary` slot only. The rule's line, passed to [cli::rule()]'s `line`: a line type (`1`-`8`, `"double"`, ...) or the string to repeat (`"-"` in the ascii preset). |
#' @export
#' @examples
#' logtree_theme("ascii")
#' logtree_theme("unicode")
#' logtree_theme(overrides = list(success = list(glyph = "*")))
#' # The close ("Done") tick is its own slot, restyled independently:
#' logtree_theme(overrides = list(done = list(glyph = "=", color = "silver")))
#' logtree_theme(overrides = list(group = list(glyph = "#", bracket = TRUE)))
#' logtree_theme(overrides = list(crumb = list(glyph = " / ", path_color = "cyan")))
#' logtree_theme(overrides = list(summary = list(gap = 2, rule = "Run report")))
#' logtree_theme("unicode")
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
  # Only the status slots the theme actually carries: a hand-built theme (or one
  # created before a slot existed) may be missing some, and a missing slot must
  # not break column alignment for the rest.
  slots <- theme[intersect(glyph_keys, names(theme))]
  max(vapply(slots, function(g) g$width, integer(1)))
}

# Status slot a close ("Done") line renders with. A clean close reads the
# `done` slot rather than `success`, so the completion tick and the
# log_success() leaf glyph are themeable independently; every other status
# (warning / error / interrupted) keeps its own slot. Themes with no `done`
# entry fall back to `success`, the pre-`done` behaviour.
close_glyph_key <- function(status, theme = the$theme) {
  if (identical(status, "success") && !is.null(theme$done)) "done" else status
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
