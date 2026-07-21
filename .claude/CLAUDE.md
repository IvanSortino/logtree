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
  — each `debug/*.R` script is a standalone, runnable demo of one feature area.
  **Add a new `debug/*.R` script whenever you add a feature** (established
  convention: `01_simple_log.R` … `06_group_styling.R`, one file per capability).

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
  `finalize_step()` marks it `"incomplete"` (dimmed glyph) rather than showing a
  false success.

### Grouping (`R/state.R`)

`log_step(label, group_by = c(name = value))` collapses adjacent steps sharing the
same `value` under one synthetic `kind = "group"` stack entry (a header-only,
non-closing parent). `open_or_reuse_group()` reuses the top-of-stack group if the
incoming `(name, value)` matches; `settle_groups()` pops any lingering
(member-less) group that doesn't match before pushing a new entry — grouping is
strictly **adjacency-based**, not global (the same value recurring non-adjacently
opens a fresh group). A plain leaf or ungrouped step at the group's level also
triggers `settle_groups()`, closing the group as a sibling rather than nesting under
it.

### Rendering

`format_open()` / `format_close()` / `format_leaf()` / `format_group_header()`
(`R/step.R`) are pure functions of `(entry, theme, color)` — they compute the
rails+connector prefix from depth and the active theme, so the same logic backs
every sink regardless of theme or ANSI color. Rendering follows a **corner-on-close,
zero-buffer** strategy: every child line uses the branch connector, and the corner
connector is only ever a step's own close line (see design doc §3.5) — required
because this is a *live* streaming logger that can't know in advance whether a line
is the last sibling.

### Theme system (`R/glyphs.R`, `R/theme.R`)

Three built-in presets (`glyphs_unicode`, `glyphs_ascii`, `glyphs_emoji`) are plain
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
`group`, `leaf`.

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
