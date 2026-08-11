# Call-site capture for the `trace` theme slot.
#
# A trace is a plain list of three fields -- `fn` (the enclosing function's
# name), `file` and `line` (where the log call itself sits) -- each
# NA when unavailable. Rendering is in R/step.R (format_trace_field); this file
# only answers "where was I called from?".
#
# Availability differs between the two halves, and the difference is load-bearing:
#
#   * `fn` comes from the frame stack, so it is always available inside a
#     function and NA only at top level.
#   * `file`/`line` come from source references, which exist only when the code
#     was parsed with keep.source = TRUE. That is the default interactively and
#     under devtools::load_all(), but NOT under plain `Rscript` and not for an
#     installed package. So a trace routinely carries `fn` and no location, and
#     the renderer has to degrade rather than print NA.
#
# Everything here is gated by trace_enabled() at the call sites: with the slot
# off (the default in every preset) none of it runs.

# The statuses a trace can be asked for, which are the package's own status
# vocabulary -- the strings that key the theme's glyph slots and that
# status_severity() (R/leaves.R) ranks. Each names the line kind that can carry
# it: "running" is an open line, "interrupted" a close line that unwound, and
# the rest are leaves of that status.
trace_statuses <- c("running", "info", "debug", "success", "warning", "error",
                    "interrupted")

# The active `trace$show` setting, normalised to either FALSE or a character
# vector of statuses. Normalising the two shorthands away here is what lets
# every line-level decision downstream be a single `%in%`:
#
#   TRUE         every status
#   "problems"   warning and error leaves, plus interrupted close lines
#   c(...)       the statuses named, unknown tokens dropped
#
# Anything else -- a typo'd string, a stray number, a set that named nothing
# real -- reads as FALSE, matching how the `elapsed` slot's fields are
# defensively checked at use rather than validated when set.
resolve_trace_show <- function(theme = the$theme) {
  show <- theme_field("trace", "show", FALSE, theme)
  if (isTRUE(show)) return(trace_statuses)
  if (!is.character(show)) return(FALSE)
  show <- show[!is.na(show)]
  if (identical(show, "problems")) {
    return(c("warning", "error", "interrupted"))
  }
  show <- intersect(show, trace_statuses)
  if (length(show) == 0L) FALSE else show
}

# Is any trace wanted at all? The gate on every capture site, and the reason
# the default path costs one list lookup rather than a frame walk.
#
# Capture and rendering are separate stages, and the split is the thing to keep
# straight: resolve_trace_show() decides what a *line* renders, this decides
# whether anything is *recorded* in the first place. Only the second can be
# changed after the fact -- a call site not captured while the run happened
# cannot be recovered later, because the frame stack it came from is gone. That
# is why logtree_summary(trace = ) can narrow a digest but never populate one.
#
# Three things can ask for capture, hence not a pure function of the theme:
#
#   * `show` -- rendering implies recording.
#   * `capture` -- the slot's own switch, for "record call sites, print none":
#     a quiet console with an annotated digest, or a JSON sink carrying
#     locations the terminal never showed.
#   * a file sink registered with an explicit `trace = `, which wants call
#     sites even when the console column is off.
#
# It only ever adds: `capture = FALSE` (the default in every preset) does not
# take capture away from a `show` that asked for it.
trace_enabled <- function(theme = the$theme) {
  !isFALSE(resolve_trace_show(theme)) ||
    isTRUE(theme_field("trace", "capture", FALSE, theme)) ||
    length(the$trace_sinks) > 0L
}

# The file and line of a call, or NA for all fields when no source reference is
# available. src_location() (R/step.R) is the "file:line" view of this, kept for
# the srcref reconcile that predates the trace feature.
#
# Three fields, not two: `file` is what gets *printed* and `path` is what gets
# *linked*. A bare basename is unresolvable -- neither a terminal's own path
# detection nor a hyperlink can find `24_trace.R` when the file is really
# `debug/24_trace.R` -- so `file` is the working-directory-relative path where
# there is one, and `path` carries the absolute form for the link target.
src_parts <- function(call) {
  line <- utils::getSrcLocation(call, "line")
  if (is.null(line) || is.na(line)) {
    return(list(file = NA_character_, line = NA_integer_, path = NA_character_))
  }
  full <- utils::getSrcFilename(call, full.names = TRUE)
  if (is.null(full) || !nzchar(full)) {
    return(list(file = "<text>", line = as.integer(line), path = NA_character_))
  }
  abs <- normalizePath(full, winslash = "/", mustWork = FALSE)
  list(file = display_path(abs),
       line = as.integer(line),
       path = if (file.exists(abs)) abs else NA_character_)
}

# The shortest view of a source file that a terminal can still resolve:
# relative to the working directory when the file sits under it, the bare file
# name otherwise (a package installed elsewhere, say, where no short form would
# have resolved anyway).
display_path <- function(abs) {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  if (startsWith(abs, paste0(wd, "/"))) return(substring(abs, nchar(wd) + 2L))
  basename(abs)
}

# The name of the function a call belongs to, or NA. rlang::call_name() returns
# NULL for anything that is not a simple `f(...)` -- a call through a function
# value, an infix operator -- which is a legitimate outcome here, not an error.
call_fn_name <- function(call) {
  if (is.null(call)) return(NA_character_)
  fn <- rlang::call_name(call)
  if (is.null(fn)) return(NA_character_)
  fn
}

# A trace for a call site found by walking the frame stack.
#
# `call` is the log call itself, and supplies file/line. `up` says how many
# frames above *the caller of this function* the user's own function sits:
# log_step() passes 1 (its caller is the user's function), while emit_leaf()
# passes 2 (the log_info()/log_warn()/... wrapper sits in between).
#
# The frame arithmetic is done here, in one place, using absolute frame numbers
# rather than sys.call()'s negative offsets: a negative offset past the bottom
# of the stack is an error, whereas an absolute index below 1 is simply "called
# from top level", which is the answer we want.
capture_trace <- function(call, up = 1L) {
  # +1 for capture_trace()'s own frame: `up` is counted from our caller.
  idx    <- sys.nframe() - (up + 1L)
  target <- if (idx >= 1L) sys.call(idx) else NULL
  loc    <- src_parts(call)
  list(fn = call_fn_name(target), file = loc$file, line = loc$line,
       path = loc$path)
}

# A trace for a call we were handed rather than one we had to find.
#
# Two callers, both of which would otherwise trace to the wrong place:
# with_logging()'s error handler, which holds conditionCall(cnd) -- the call
# that threw -- and layout_logtree(), which receives logger's `.topcall`. Both
# log from inside a frame of their own, so a frame walk would name the handler
# or the layout instead of the user's code.
#
# Note the asymmetry with capture_trace(): here `fn` and the location come from
# the *same* call, so the location is where that function was called, not where
# the log line sits. For a thrown error that is the more useful of the two.
#
# Unlike capture_trace(), this one carries its own gate. Its callers hand it a
# call they happen to be holding rather than choosing to go looking for one, so
# it is easy to forget to guard -- and an ungated trace would reach the JSON sink
# as populated fields on a run where the feature is switched off.
trace_from_call <- function(call) {
  if (is.null(call) || !trace_enabled()) return(NULL)
  loc <- src_parts(call)
  list(fn = call_fn_name(call), file = loc$file, line = loc$line,
       path = loc$path)
}
