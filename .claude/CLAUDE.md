# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

`logtree` is an R package that renders nested process execution as a live, colored
tree in the console (`▶`/`✔`/`⚠`/`✖`, tree connectors, elapsed time per step),
staying correct even when a step errors partway through. It builds on `cli` for
console rendering, `rlang` for caller-frame introspection, and `withr` for deferred
cleanup. `logtree-design-doc.md` (repo-only, excluded from the built package via
`.Rbuildignore`) is the authoritative design rationale — consult it for the *why*
behind architectural decisions referenced below.

## Development commands

- Load the package for interactive use: `devtools::load_all()`
- Run the full test suite: `devtools::test()`
- Run a single test file: `devtools::test(filter = "grouping")` (matches
  `test-grouping.R`) or `testthat::test_file("tests/testthat/test-grouping.R")`
- Regenerate `NAMESPACE`/`man/*.Rd` from roxygen comments: `devtools::document()` —
  `NAMESPACE` is roxygen2-generated, never hand-edit it
- Full CRAN-style check: `devtools::check()` (target: 0 errors/warnings/notes)
- Rebuild `README.md` from `README.Rmd`: `devtools::build_readme()`
- Run a feature demo: `Rscript -e 'devtools::load_all(); source("debug/01_simple_log.R")'`
  — each `debug/*.R` script is a standalone, runnable demo of one feature area,
  numbered contiguously (`01_simple_log.R` … `14_srckey_replay.R`, one file per
  capability). **Add a new numbered `debug/*.R` script whenever you add a
  feature.** Non-demo build/release helpers (README-asset regen, CRAN checklist)
  live under `debug/maintenance/`, kept out of the numbered demo sequence.

## Architecture

### Core state & step lifecycle

All state lives in a single package-private environment `the` (`R/state.R`): an
open-step `stack` (list of step/group entries) and a `next_id` counter. `log_step()`
(`R/step.R`) pushes a stack entry and registers its close via
`withr::defer(..., envir = rlang::caller_env(), priority = "first")` — **in the
caller's frame, not inside `log_step()` itself**. That's what makes nesting depth
self-correcting: the close fires when the calling function's frame exits, whether by
normal return, early `return()`, or an uncaught error unwinding through it. No
step can ever leak and desync later indentation.

### Status elevation (two tiers, `R/leaves.R` / `R/step.R`)

- **Tier 1 (always on):** `log_warn()`/`log_error()` call `elevate_current_step()`,
  which bumps the nearest open *step* entry's status (`running < success < warning <
  error` via `status_severity()`) without the step itself throwing.
- **Tier 2 (opt-in via `with_logging()`, `R/run.R`):** installs a
  `withCallingHandlers(error = ...)` that marks every currently-open step `"error"`
  and logs the condition message as a leaf *before* the stack unwinds, then rethrows
  — `with_logging()` never swallows errors.
- If a step's frame exits abnormally with no Tier-2 handler having elevated it,
  `finalize_step()` marks it `"interrupted"` (dimmed glyph) rather than showing a
  false success.

### Grouping (`R/state.R`)

`log_step(label, group = c(name = value))` collapses adjacent steps sharing the
same `value` under one synthetic `kind = "group"` stack entry — a header line on
open and its own corner close line on pop (a `group_close` event rendered via the
same `format_close()` as a step). The group is not tied to any frame: it lingers
after its last member closes until popped. Its close line's status is **aggregated
from its members** — `close_step()` folds each closing member's resolved status up
into the parent group via `elevate_group_status()`, so a group with a failed member
closes with the error glyph. `open_or_reuse_group()` reuses the top-of-stack group
if the incoming `(name, value)` matches; `settle_groups()` closes any lingering
group that doesn't match before pushing a new entry — grouping is strictly
**adjacency-based**, not global (the same value recurring non-adjacently opens a
fresh group). A plain leaf or ungrouped step at the group's level also triggers
`settle_groups()`, closing the group as a sibling rather than nesting under it.

### Rendering

`format_open()` / `format_close()` / `format_leaf()` / `format_group_header()`
(`R/step.R`) are pure functions of `(entry, theme, color)` — they compute the
rails+connector prefix from depth and the active theme, so the same logic backs
every sink regardless of theme or ANSI color. Rendering follows a **corner-on-close,
zero-buffer** strategy: every child line uses the branch connector, and the corner
connector is only ever a step's own close line (see design doc §3.5) — required
because this is a *live* streaming logger that can't know in advance whether a line
is the last sibling.

### Call-site trace (`R/trace.R`)

The opt-in `trace` theme slot annotates lines with `file.R:line fn()`.
`capture_trace()` walks the frame stack for the enclosing function's name;
`src_parts()` reads the srcref for file/line (and `src_location()`, the older
"file:line" view used by the srckey reconcile, now delegates to it). Capture is
gated by `trace_enabled()` and so costs nothing on the default path — `show` is
`FALSE` in every preset. `resolve_trace_show()` normalises `show` to **`FALSE`
or a character vector of statuses** (`trace_statuses`: running, info, debug,
success, warning, error, interrupted), resolving the `TRUE` and `"problems"`
shorthands away there so every line-level decision is one `%in%` —
`format_trace_field()` tests `"running"` for open lines and the line's own
status otherwise, and `format_trace_digest()` tests the entry's status. The one
rule that is not membership: an ordinary close line never carries a trace (its
site is its own open line's), only an interrupted one. **`{file}`/`{line}` require `keep.source`**, absent
under plain `Rscript`, so `expand_trace_text()` drops any template run whose
placeholders are all unavailable rather than rendering `NA`.

`src_parts()` returns three fields, not two: `file` is the *printed* form
(relative to `getwd()` when the source sits under it — a bare basename resolves
to nothing) and `path` is the absolute form used as the hyperlink target.
Styling and linking happen in `expand_trace_text()`, *after* the
run-availability check, so a styled empty value can never keep a run alive. A
run mentioning `{file}`/`{line}` is a **location** and is styled and linked as
one unit (separator included, one OSC 8 span); any other run styles its
placeholders individually, which is what leaves `{fn}` coloured and its `()` in
the base colour. `trace$color` therefore takes either a character vector (the
whole column, becoming `base`) or a `list(base=, location=, fn=)`, which is
what the coloured presets ship.
`trace_link()` emits OSC 8 via `cli::style_hyperlink()`, which no-ops on
terminals without support; the escape has zero printable width, so
`compose_line()`'s wrapping arithmetic is untouched.

The column is appended to the *message* before it reaches `compose_line()`, which
is why none of the `cols`/`cont` layout arithmetic changed. Two handlers are
handed their call site rather than walking for it, because they log from inside a
frame of their own and a walk would name the handler: `with_logging()` via
`conditionCall()` (`log_error_at()`), and `layout_logtree()` via `logger`'s
`.topcall`. Both pass `emit_leaf(capture = FALSE)` so a NULL call site cannot
silently fall through to the wrong answer.

### Theme system (`R/glyphs.R`, `R/theme.R`)

Five built-in presets (`glyphs_unicode`, `glyphs_ascii`, `glyphs_emoji`,
`glyphs_minimal`, `glyphs_ci`) are plain
named lists keyed by status/connector, each glyph entry declaring its own `width`
explicitly rather than measured (`nchar()`/`ansi_nchar()` can't reliably size emoji
cells) — this is what keeps message text column-aligned across themes.
`logtree_theme()` either swaps the whole preset or merges a named list of
per-key overrides onto the active theme via `utils::modifyList()`. **Non-ASCII
glyphs must be written as `\u`/`\U` escapes, never literal characters** — a hard
CRAN portability requirement for package R source.

### Appenders / sinks (`R/appenders.R`)

`emit()` fans every event out to all registered `the$sinks`. The console sink is
always on; `logtree_sink_file(path, format = c("text", "json"))` adds a plain-ASCII
text sink or an NDJSON sink (hand-rolled scalar encoder — deliberately no `jsonlite`
dependency for this fixed, small event shape). Event kinds are `open`, `close`,
`group` (group header), `group_close` (group corner/close line), `leaf`.

## Testing conventions

- Every test must reset global state: `logtree_reset()` at the start plus
  `withr::defer(logtree_reset())`, since the stack/id-counter are package-global.
- `helper-clock.R`'s `freeze_clock(times)` mocks `now()` via
  `testthat::local_mocked_bindings()` so elapsed-time snapshot tests are
  deterministic.
- `helper-sinks.R`'s `local_reset_sinks()`, `helper-theme.R`'s
  `local_ascii_theme()`, and `helper-verbosity.R`'s `local_reset_verbosity()` scope
  sink/theme/verbosity changes to the current test via `withr::defer()`. Tests that
  assert on rendered output generally call `local_ascii_theme()` first, since ASCII
  output is theme-stable and easy to pattern-match.
- Snapshot tests (`testthat::expect_snapshot`) live under `tests/testthat/_snaps/`.

## CRAN-compliance constraints

This package targets `R CMD check --as-cran` with 0 errors/warnings/notes
(`logtree-design-doc.md` §8 has full detail). The two constraints most likely to
matter when editing code:

- All exported and internal side-effecting functions return `invisible(...)`; never
  print on package load (`.onLoad` in `R/zzz.R` only sets defaults, no output).
- Any example or debug script that writes a file sink must target
  `tempfile()`/`tempdir()`, never the working directory.
