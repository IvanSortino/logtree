glyph_keys <- c("step", "debug", "info", "success", "done", "warning", "error",
                "interrupted")

theme_presets <- c("unicode", "ascii", "emoji", "minimal", "ci")

theme_preset <- function(name) {
  switch(name,
    unicode = glyphs_unicode,
    ascii   = glyphs_ascii,
    emoji   = glyphs_emoji,
    minimal = glyphs_minimal,
    ci      = glyphs_ci,
    stop("Unknown theme preset: ", name, call. = FALSE)
  )
}

# A preset as the *console* theme carries: the presets themselves are plain
# glyph tables, and wrapping is a property of the sink rather than of the
# glyphs. Wrapping on at the terminal width is the default -- a long message
# reads better wrapped than run off the right edge -- and it is set here, not
# in the presets, precisely so that file sinks (which render through
# `glyphs_ascii` directly, and have no width to wrap to) stay unwrapped.
console_preset <- function(name) {
  preset <- theme_preset(name)
  preset$wrap <- TRUE
  preset
}

# Resolve the `compact` argument of logtree_theme() to NULL / "medium" / "tight".
resolve_compact <- function(x) {
  if (is.null(x) || isFALSE(x)) return(NULL)
  if (isTRUE(x)) return("tight")
  match.arg(x, c("medium", "tight"))
}

# Resolve the `connector_gap` argument of logtree_theme() to NULL (leave as
# is) or a non-negative integer count of spaces.
resolve_connector_gap <- function(x) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 0) {
    stop("`connector_gap` must be a single non-negative number.", call. = FALSE)
  }
  as.integer(x)
}

# Resolve the `glyph_gap` argument of logtree_theme() to NULL (leave as is) or
# a non-negative integer count of spaces.
resolve_glyph_gap <- function(x) {
  if (is.null(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 0) {
    stop("`glyph_gap` must be a single non-negative number.", call. = FALSE)
  }
  as.integer(x)
}

# Resolve the `wrap` argument of logtree_theme() to NULL (leave as is), a
# logical, or a positive integer column count. TRUE is kept as a logical rather
# than resolved to a number here, so the width is measured at render time and a
# terminal resized mid-run is picked up without re-setting the theme.
resolve_wrap <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.logical(x) && length(x) == 1L && !is.na(x)) return(x)
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 1) {
    stop("`wrap` must be TRUE, FALSE, or a single positive number of columns.",
         call. = FALSE)
  }
  as.integer(x)
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
  # A preset with no connector glyph at all -- `minimal` -- carries its entire
  # indentation in col_gap, so zeroing it would leave a per-level column of
  # zero: every depth would render at the left margin and the tree would read
  # as a flat list. Compact is meant to tighten the tree, never to erase it, so
  # keep one column per level for connectorless themes.
  if (!nzchar(the$theme$branch$glyph)) the$theme$col_gap <- 1L
  invisible(NULL)
}

# Merge an override list onto the active theme, one slot at a time. A mistyped
# slot is caught here rather than reaching modifyList(), whose
# "is.list(x) is not TRUE" names neither the offending slot nor the valid ones.
# Only list-valued slots can be overridden -- scalars such as `col_gap` are
# theme internals, set through logtree_theme()'s `compact` argument.
apply_overrides <- function(overrides) {
  if (length(overrides) == 0L) return(invisible(NULL))
  if (is.null(names(overrides)) || any(!nzchar(names(overrides)))) {
    stop("`overrides` must be a named list, keyed by theme slot.", call. = FALSE)
  }
  slots   <- names(the$theme)[vapply(the$theme, is.list, logical(1))]
  unknown <- setdiff(names(overrides), slots)
  if (length(unknown) > 0L) {
    stop(
      "Unknown theme slot", if (length(unknown) > 1L) "s" else "", ": ",
      paste0("`", unknown, "`", collapse = ", "), ".\n",
      "Valid slots: ", paste(slots, collapse = ", "), ".",
      call. = FALSE
    )
  }
  for (key in names(overrides)) {
    the$theme[[key]] <- utils::modifyList(the$theme[[key]], overrides[[key]])
  }
  invisible(NULL)
}

#' Set the active glyph/color theme
#'
#' @param theme Either a preset name to swap the whole glyph set, or a named
#'   list of per-key overrides to merge onto the currently active theme
#'   (matching the two calling styles shown in the package documentation).
#'   `NULL` (the default) keeps the active preset: **a preset is swapped only
#'   when you name one**, so a call that sets just `overrides`, `compact`,
#'   `glyph_gap`, `connector_gap` or `wrap` merges onto whatever theme is
#'   active. Reset with
#'   `logtree_theme("unicode")`. Five presets ship with the package:
#'
#'   | Preset | What it is for |
#'   | ------ | -------------- |
#'   | `"unicode"` | The default. Box-drawing connectors and coloured symbol glyphs, for an interactive terminal. |
#'   | `"ascii"` | Plain ASCII, no colour. Safe for log files, CI, and non-UTF-8 terminals; also what every file sink renders through. |
#'   | `"emoji"` | Emoji status glyphs (width-2 cells) over box-drawing connectors. |
#'   | `"minimal"` | No connectors at all: `branch`, `corner` and `pipe` are empty, so depth is carried by indentation alone (two columns per level). Lighter glyphs, dimmed times, wordless close lines. `info`, `debug` and `interrupted` share the middle dot and are told apart by colour. |
#'   | `"ci"` | Bracketed word glyphs (`[step]`, `[ok]`, `[warn]`, `[fail]`, ...) over pure-ASCII connectors, with no colour in any slot -- so a captured build log survives a runner that strips ANSI, and a failure greps as `[fail]`. |
#' @param overrides A named list of per-slot overrides applied on top of
#'   `theme` once it is resolved -- on top of the *active* theme when `theme`
#'   is `NULL`. An unknown slot name is an error, listing the valid ones. Each
#'   entry names only the fields to change; unspecified fields are kept from
#'   the existing entry. Status slots take `glyph`, `width` and `color`; the
#'   close-line statuses (`done`, `warning`, `error`, `interrupted`) also take
#'   `text`. The `group` slot takes `bracket`, the `elapsed` slot governs the
#'   time column on close lines, and the two non-glyph slots `crumb` and
#'   `summary` carry [logtree_summary()]'s appearance. See the slot and field
#'   tables below for the complete set.
#' @param compact Density of the tree's per-level indentation. `FALSE` (the
#'   default) keeps the normal spacing (three columns per level in the unicode
#'   theme); `"medium"` drops the trailing gap after each connector (two columns
#'   per level); `"tight"` additionally slims the branch and corner connectors
#'   to a single character (one column per level). `TRUE` is an alias for
#'   `"tight"`. Compact applies to the active (console) theme and is cleared by a
#'   subsequent preset swap such as `logtree_theme("unicode")`.
#' @param glyph_gap Number of spaces printed between a line's status glyph and
#'   its message text. `NULL` (the default) leaves the active setting alone;
#'   `1` is the built-in spacing, `0` butts the message straight against the
#'   glyph, and `2` or more airs the two columns apart. Applies to every line
#'   kind -- step open, `Done` close, leaf, group header and the
#'   [with_logging()] run-summary line -- so the message column stays aligned.
#'   Like `compact`, it applies to the active (console) theme and is cleared by
#'   a subsequent preset swap such as `logtree_theme("unicode")`.
#' @param connector_gap Number of spaces printed between a *leaf or close*
#'   line's own connector and its status glyph -- `log_info()`/`log_warn()`/
#'   etc. lines and a step's own `Done` line, never a step's *open* line
#'   (which always renders flush, at any `compact` density). `NULL` (the
#'   default) leaves the active setting alone, which tracks `col_gap` (so
#'   every built-in preset, and `compact = "medium"`/`"tight"`, render exactly
#'   as before). Set it explicitly to diverge from `col_gap` -- e.g. pair it
#'   with `compact = "tight"` to keep every rail column flush (`col_gap = 0`,
#'   including step-open lines) while still spacing leaf/close glyphs off
#'   their own connector. Like `glyph_gap`, it applies to the active (console)
#'   theme and is cleared by a subsequent preset swap.
#' @param wrap Column budget a rendered line is wrapped to, instead of letting
#'   a long message run off the right edge. `TRUE` wraps at
#'   [cli::console_width()], measured at render time so a terminal resized
#'   mid-run is picked up on its own -- this is the console default; a
#'   positive number pins a fixed width; `FALSE` never wraps, letting long
#'   lines overflow. `NULL` (the argument default) leaves the active setting
#'   alone.
#'
#'   Continuation lines indent to the message column and carry the rails down,
#'   so a wrapped message still reads as one node of the tree: after a branch
#'   connector the vertical rail continues, after a corner it does not. A
#'   step-open line (and a group header) also rails its own glyph column,
#'   which is where its children hang -- on a depth-1 root that is the only
#'   rail there is. A leaf's glyph column stays blank: nothing nests under a
#'   leaf. A token with no break opportunity -- a long path, a URL -- is split
#'   by display width rather than left to overflow, and a budget narrower than
#'   the tree is deep degrades to no wrapping rather than to an unusable
#'   one-column line.
#'   It applies to every line logtree renders, including the
#'   [logtree_summary()] digest and the [with_logging()] run-summary line.
#'
#'   Like `compact` and `glyph_gap`, it applies to the active (console) theme,
#'   and a subsequent preset swap returns it to the `TRUE` default. File sinks
#'   are never wrapped: they render through the ascii preset, and a file has no
#'   width to wrap to.
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
#' | `done` | a step's own close line on a clean close | `glyph`, `width`, `color`, `text` |
#' | `warning` | `log_warn()` / elevated step glyph | `glyph`, `width`, `color`, `text` |
#' | `error` | `log_error()` / elevated step glyph | `glyph`, `width`, `color`, `text` |
#' | `interrupted` | abnormal-exit (dimmed) glyph | `glyph`, `width`, `color`, `text` |
#' | `group` | group header marker | `glyph`, `color`, `bracket` |
#' | `elapsed` | the elapsed-time column printed on every close line | `show`, `min`, `color`, `slow`, `slow_color` |
#' | `trace` | the optional call-site column: where in your code a line came from | `show`, `capture`, `format`, `color` |
#' | `timestamp` | the optional wall-clock column printed in front of every line | `format`, `color` |
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
#' The same split governs the `text` field, the word a close line prints before
#' its elapsed time. It is read from the closing status's own slot, falling back
#' to `done`'s and then to the built-in `"Done"` -- so
#' `list(done = list(text = "Complete"))` renames every close line, while
#' `list(error = list(text = "Failed"))` renames only the ones that went wrong.
#' `success` has no `text` of its own precisely because a clean close reads
#' `done`. `text` is a close-line concern only: it never touches the message a
#' [log_warn()] or [log_error()] leaf prints.
#'
#' The `trace` slot is off in every preset, and deliberately so: capturing a call
#' site costs a frame walk and a source-reference lookup on every logged line, so
#' you opt in and the default path pays nothing. Switch it on with
#' `list(trace = list(show = "problems"))` to annotate only what went wrong, or
#' `show = TRUE` for every line that can carry a call site. `show` also takes a
#' vector of statuses, for when the bundle is too much: `show = "error"`
#' annotates errors and leaves tolerated warnings bare, `show = c("error",
#' "interrupted")` adds the steps that never finished. The column is appended to
#' the message, so it wraps with it rather than shearing the tree.
#'
#' The location -- `{file}` and `{line}` together, separator included -- is also
#' emitted as one terminal hyperlink pointing at the file, at that line, so a
#' click anywhere on it opens your editor there. Terminals without
#' hyperlink support print the same text unlinked, and the escape has no
#' printable width either way. `{file}` prints relative to the working directory
#' where the source sits under it -- a bare file name is not something a
#' terminal can resolve.
#'
#' **On source references.** `{file}` and `{line}` come from R's source
#' references, which exist only when the code was parsed with `keep.source =
#' TRUE`. That is the default in an interactive session and under
#' `devtools::load_all()`, but **not** under plain `Rscript` and not for an
#' installed package. `{fn}` is always available. Rather than print `NA`, the
#' expander drops any whitespace-separated run of the template whose placeholders
#' are all unavailable -- so the default format degrades from
#' `pipeline.R:12 load_data()` to `load_data()`, and a `"{file}:{line}"` format
#' degrades to no column at all. Set `options(keep.source = TRUE)` at the top of
#' a script if you want locations under `Rscript`.
#'
#' Capturing and printing are separate: `show` decides what a line *prints*,
#' `capture = TRUE` decides that call sites are *recorded* whatever `show`
#' prints. `list(trace = list(show = FALSE, capture = TRUE))` therefore leaves
#' the tree exactly as it was while giving the digest and any `"json"` sink
#' locations to work with. The order matters -- capture happens as the run
#' unfolds, so a call site not recorded then cannot be recovered afterwards.
#'
#' The `timestamp` slot is off in every preset for a different reason: a tree
#' read as it happens does not need to be told the time, and a column that is not
#' there is one the message has room for. It is the log read *afterwards* that
#' wants it -- lining a run up against a monitoring graph, another service's log,
#' or a report that something broke at about half past two. Switch it on with
#' `list(timestamp = list(format = "%H:%M:%S"))`.
#'
#' The column is padded to a fixed width measured from a rendered sample, not
#' from the format string, so a format whose width varies with the value (`"%B"`,
#' `March` one month and `December` the next) cannot shear the tree from one
#' line to the next. It counts against
#' the wrapping budget like any other column, and a wrapped message's
#' continuation rows carry a *blank* column rather than a repeated time -- one
#' event happened once. [logtree_summary()]'s digest carries no timestamp at all:
#' it replays events that already happened, so stamping those lines with the time
#' the digest was printed would be a lie.
#'
#' Two places outside the tree also report call sites when the slot is on:
#' [logtree_summary()]'s digest lines, which apply the same status filter as the
#' tree does, and the `fn` / `file` / `line` fields of a `"json"` sink (which
#' carries them whenever they were captured, regardless of `show`). See
#' [logtree_sink_file()] for pinning a file sink's column independently of the
#' console's.
#'
#' **Fields** (valid names inside a slot):
#'
#' | Field | Type | Accepted values |
#' | ----- | ---- | --------------- |
#' | `glyph` | `character(1)` | Any string, including `""`. In package source, non-ASCII must be written as `\u`/`\U` escapes, never literal characters. |
#' | `width` | `integer(1)` | Rendered display width of `glyph` (`1` for normal, `2` for emoji / wide cells). Drives column alignment and cannot be measured, so set it to the true width. Status slots only (`step`, `info`, `debug`, `success`, `done`, `warning`, `error`, `interrupted`). |
#' | `color` | `character`, `NULL`, or a named `list` on `trace` | One or more cli styles, or `NULL` for no styling. Named colors (`"red"`, `"cyan"`, `"silver"`, ...), bright variants (`"br_red"`), backgrounds (`"bg_blue"`), text styles (`"bold"`, `"italic"`, `"dim"`), or a hex string (`"#ff8800"`). A character vector combines styles, e.g. `c("red", "bold")`. On the `elapsed` slot it styles the time itself. On `trace` it also accepts a named list styling the parts of the column separately: `location` for a `{file}`/`{line}` run (the separator between them included -- the location is one thing, styled and linked whole), `fn` for the function name, and `base` for everything else, which in the default format is the `()`. That is what the coloured presets ship: all of it dim, with the location in silver and `fn` in cyan, so the two read apart. A plain character vector on `trace` styles the whole column. `NULL` in the colourless ascii and ci presets. See [cli::combine_ansi_styles()]. |
#' | `text` | `character(1)` | Close-line status slots only (`done`, `warning`, `error`, `interrupted`). The word a close line prints before its elapsed time; `""` drops it, leaving the glyph and the time. Two placeholders are expanded: `{label}` (the closing step's own label, or a group's name) and `{elapsed}` (the formatted time). A template that places `{elapsed}` itself owns that column, so the time is not appended after it a second time. |
#' | `show` | `logical(1)`, or `character` on `trace` | On `elapsed`: `FALSE` drops the elapsed-time column entirely, default `TRUE`. On `trace`: `FALSE` (the default in every preset) off entirely; `TRUE` every line that can carry a call site; `"problems"` a shorthand for `c("warning", "error", "interrupted")`; or a vector of statuses naming exactly what to annotate -- `"running"` (open lines), `"info"`, `"debug"`, `"success"`, `"warning"`, `"error"` (leaves of that status) and `"interrupted"` (a close line whose step unwound). `show = "error"` is errors without their warnings. An ordinary close line never carries one whatever the set: its site is its own open line's. Unknown tokens are dropped, and anything unrecognised reads as `FALSE`. |
#' | `format` | `character(1)` | On `trace`: a template for the call-site column over three placeholders: `{fn}` (the enclosing function's name), `{file}` and `{line}` (where the log call sits). Default `"{file}:{line} {fn}()"`. A whitespace-separated run whose placeholders are *all* unavailable is dropped whole, so the default degrades to `load_data()` rather than printing `NA` -- see the note on source references below. On `timestamp`: a [strftime] format such as `"%H:%M:%S"` or `"%Y-%m-%d %H:%M:%S"`, or `NULL` (the default in every preset) for no column at all. |
#' | `capture` | `logical(1)` | `trace` slot only. `TRUE` records a call site on every line even where `show` prints none, for "record, print later": a quiet console whose [logtree_summary()] digest or `"json"` sink still carries locations. Default `FALSE` in every preset. It only ever adds -- a `show` that asks for a column already implies capture, and `capture = FALSE` never takes that away. This is the one part of the feature that cannot be decided after the fact: a call site not recorded while the run happened is gone, because the frame stack it came from has unwound. |
#' | `min` | `numeric(1)` | `elapsed` slot only. Hide times below this many seconds -- `min = 0.1` silences the `0.00s` noise on trivial steps. Default `0` (show everything). |
#' | `slow` | `numeric(1)` or `NULL` | `elapsed` slot only. Times at or over this many seconds count as slow and are styled with `slow_color` instead of `color`. `NULL` (the default) means nothing is ever flagged. |
#' | `slow_color` | `character` or `NULL` | `elapsed` slot only. Styles applied to a slow time in place of `color`. Same accepted values as `color`; `"yellow"` in the unicode, emoji and minimal presets, `NULL` in the colourless ascii and ci presets. |
#' | `bracket` | `logical(1)` | `group` slot only. `TRUE` wraps the header name in `< >`; default `FALSE`. |
#' | `path_color` | `character` or `NULL` | `crumb` slot only. Styles the breadcrumb's path nodes, setting them apart from a leaf's message (which stays unstyled). Same accepted values as `color`; `"bold"` in the unicode and emoji presets, `NULL` in ascii. |
#' | `gap` | `integer(1)` | `summary` slot only. Blank lines printed above the digest; `0` prints it flush against the tree. |
#' | `rule` | `logical(1)` or `character(1)` | `summary` slot only. `TRUE` draws a [cli::rule()] labelled with the digest header, `FALSE` draws none, a string sets a custom title. |
#' | `line` | `integer(1)` or `character(1)` | `summary` slot only. The rule's line, passed to [cli::rule()]'s `line`: a line type (`1`-`8`, `"double"`, ...) or the string to repeat (`"-"` in the ascii preset). |
#' @export
#' @examples
#' logtree_theme("ascii")
#' logtree_theme("unicode")
#'
#' # No preset named: these merge onto the active theme, whichever it is.
#' logtree_theme(overrides = list(success = list(glyph = "*")))
#' # The close ("Done") tick is its own slot, restyled independently:
#' logtree_theme(list(done = list(glyph = "=", color = "silver")))
#' logtree_theme(list(group = list(glyph = "#", bracket = TRUE)))
#' logtree_theme(list(crumb = list(glyph = " / ", path_color = "cyan")))
#' logtree_theme(list(summary = list(gap = 2, rule = "Run report")))
#'
#' # The word on a close line: every one at once, or only the failures.
#' logtree_theme(list(done = list(text = "Complete")))
#' logtree_theme(list(error = list(text = "Failed")))
#' logtree_theme(list(done = list(text = "{label} took {elapsed}")))
#' logtree_theme(list(done = list(text = "")))  # glyph + time only
#'
#' # The elapsed-time column: hide the trivial, flag the slow.
#' logtree_theme(list(elapsed = list(min = 0.1)))
#' logtree_theme(list(elapsed = list(color = "silver", slow = 5,
#'                                   slow_color = "red")))
#' logtree_theme(list(elapsed = list(show = FALSE)))
#'
#' # The call-site column: off by default, loudest on the lines that matter.
#' logtree_theme(list(trace = list(show = "problems")))
#' logtree_theme(list(trace = list(show = TRUE)))
#' logtree_theme(list(trace = list(show = "error")))          # errors only
#' # Record call sites but print none: the digest can still show them.
#' logtree_theme(list(trace = list(show = FALSE, capture = TRUE)))
#' logtree_theme(list(trace = list(show = c("error", "interrupted"))))
#' logtree_theme(list(trace = list(show = TRUE, format = "{fn}()")))
#' logtree_theme(list(trace = list(format = "{file}:{line}", color = "silver")))
#' logtree_theme(list(trace = list(show = FALSE)))  # back off again
#'
#' # The wall-clock column: off by default, in front of every line when on.
#' logtree_theme(list(timestamp = list(format = "%H:%M:%S")))
#' logtree_theme(list(timestamp = list(format = "%Y-%m-%d %H:%M:%S",
#'                                     color = "silver")))
#' logtree_theme(list(timestamp = list(format = NULL)))   # back off again
#'
#' # Naming one swaps the whole preset, clearing every override above.
#' logtree_theme("unicode")
#' logtree_theme("unicode", compact = "medium")
#' logtree_theme("unicode", compact = "tight")
#'
#' # Tight rails, but with the glyph spaced off its connector.
#' logtree_theme("unicode", compact = "tight", connector_gap = 1)
#'
#' # Spacing between the glyph and the message.
#' logtree_theme(glyph_gap = 0)   # tightest: no space after the glyph
#' logtree_theme(glyph_gap = 2)   # roomier message column
#'
#' # Wrapping long messages (on by default, at the console width).
#' logtree_theme(wrap = 72)       # pin a fixed width
#' logtree_theme(wrap = FALSE)    # let long lines overflow instead
#' logtree_theme(wrap = TRUE)     # back to the console width
#'
#' # The other two presets.
#' logtree_theme("minimal")       # no connectors: indentation only
#' logtree_theme("ci")            # [ok] / [warn] / [fail], no colour
#' logtree_theme("unicode")       # back to the default
logtree_theme <- function(theme = NULL, overrides = list(), compact = FALSE,
                          glyph_gap = NULL, connector_gap = NULL, wrap = NULL) {
  if (is.character(theme)) {
    theme <- match.arg(theme, theme_presets)
    the$theme <- console_preset(theme)
  } else if (is.list(theme)) {
    # Called as logtree_theme(list(...)) -- overrides-only, merge onto
    # whatever theme is already active.
    overrides <- theme
  } else if (!is.null(theme)) {
    stop("`theme` must be a preset name or a list of overrides.", call. = FALSE)
  }
  # theme = NULL (the default) keeps the active preset: a preset is swapped
  # only when one is named, so a call that just sets `overrides` or `compact`
  # merges onto whatever is active rather than silently reverting to unicode.

  # Apply the compact density before user overrides so explicit overrides win.
  compact <- resolve_compact(compact)
  if (!is.null(compact)) apply_compact(compact)

  # Glyph-to-message spacing rides the active theme the same way col_gap does:
  # set here, carried by the theme object, cleared by the next preset swap.
  glyph_gap <- resolve_glyph_gap(glyph_gap)
  if (!is.null(glyph_gap)) the$theme$glyph_gap <- glyph_gap

  # The connector-to-glyph gap rides the same mechanism, one level shallower:
  # it spaces a *leaf or close* line's own connector from its status glyph
  # without touching `col_gap`, so `compact = "tight"` can keep every rail
  # column -- including step-open lines -- flush while still airing out
  # leaf/close glyphs.
  connector_gap <- resolve_connector_gap(connector_gap)
  if (!is.null(connector_gap)) the$theme$connector_gap <- connector_gap

  # So does the wrap width -- the third scalar carried by the theme object
  # rather than an override slot.
  wrap <- resolve_wrap(wrap)
  if (!is.null(wrap)) the$theme$wrap <- wrap

  apply_overrides(overrides)

  invisible(NULL)
}

#' Set the minimum log level threshold to render
#'
#' Leaf lines below this level are silently skipped: `log_debug()` counts as
#' `"debug"`, `log_info()` and `log_success()` count as `"info"`, `log_warn()`
#' as `"warn"`, `log_error()` as `"error"`. Step open/close lines always
#' render regardless of verbosity, since hiding them would break the tree
#' structure.
#'
#' This is the *default* for every sink; a sink registered with its own
#' `threshold` ignores it (see [logtree_sink_file()] and [logtree_sink()]), which
#' is what lets a debug-level log file coexist with an ordinary console.
#'
#' Verbosity governs rendering only, never what the run remembers. A suppressed
#' `log_warn()`/`log_error()` still elevates the enclosing step's close glyph,
#' and still reaches the [logtree_summary()] digest -- what is hidden is the leaf
#' line's own text, not the fact that it happened.
#'
#' @param level One of `"debug"`, `"info"`, `"warn"`, `"error"` (case-insensitive).
#' @return `NULL`, invisibly.
#' @seealso [logtree_sink_file()] and [logtree_sink()] for per-sink thresholds.
#' @export
#' @examples
#' logtree_threshold("info")
logtree_threshold <- function(level = c("debug", "info", "warn", "error")) {
  the$verbosity <- match.arg(tolower(level), c("debug", "info", "warn", "error"))
  invisible(NULL)
}

# Look one field up inside one theme slot, falling back to `default`.
#
# Both lookups have to be name-guarded rather than written as
# `theme[[slot]][[field]]`: `[[` on a list *errors* for a name that is not
# there, and neither is guaranteed to be. A hand-built theme -- or one built
# before a slot existed -- may carry neither the slot nor the field, and
# modifyList() deletes an entry outright when an override sets it to NULL, so
# a field can go missing at runtime too. Every optional theme setting reads
# through here so a missing one degrades to its default instead of throwing.
theme_field <- function(slot, field, default, theme = the$theme) {
  if (!slot %in% names(theme)) return(default)
  entry <- theme[[slot]]
  if (is.null(entry) || !field %in% names(entry)) return(default)
  value <- entry[[field]]
  if (is.null(value)) default else value
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

# Spaces between a line's status glyph and its message text. Defaults to 1L
# when the theme carries no `glyph_gap` (every built-in preset), so default
# rendering is byte-for-byte unchanged; 0L butts the message straight against
# the glyph, 2L+ airs the two columns apart.
theme_glyph_gap <- function(theme = the$theme) {
  if (is.null(theme$glyph_gap)) 1L else theme$glyph_gap
}

# Spaces between a leaf or close line's own branch/corner connector and its
# status glyph (never a step-open line's, which always renders flush).
# Defaults to `col_gap` when the theme carries no `connector_gap` of its own,
# so a preset or a compact density that only sets `col_gap` renders exactly as
# before -- `connector_gap` only diverges once set explicitly, which is what
# lets `compact = "tight"` (col_gap 0, slimmed connectors) still air out
# leaf/close glyphs without widening any rail column.
theme_connector_gap <- function(theme = the$theme) {
  if (is.null(theme$connector_gap)) theme_col_gap(theme) else theme$connector_gap
}

glyph_pad <- function(theme = the$theme) {
  strrep(" ", theme_glyph_gap(theme))
}

# Column budget a rendered line is wrapped to, or NA when wrapping is off --
# which is what a bare preset carries, and so always the case for file sinks,
# which render through `glyphs_ascii` directly. The console theme is built by
# console_preset(), which turns wrapping on. TRUE measures the console at
# render time rather than at the time the theme was set, so resizing a
# terminal mid-run is picked up on its own.
theme_wrap_width <- function(theme = the$theme) {
  w <- theme$wrap
  if (is.null(w) || isFALSE(w)) return(NA_integer_)
  if (isTRUE(w)) return(as.integer(cli::console_width()))
  as.integer(w)
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
