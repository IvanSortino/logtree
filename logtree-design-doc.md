# Design Document: Tree-Style Logging Package for R

**Status:** Brainstorm / pre-implementation
**Working name:** `logtree` (placeholder — see naming options below)
**Core dependency:** `cli` (+ `rlang` for frame introspection)

---

## 1. Goal

A logging package that renders process execution as a live, colored, glyph-annotated
tree in the console — nested steps shown with tree connectors (`├─`, `└─`, `│`),
status glyphs (`✔ ⚠ ✖ ℹ`), and elapsed time per step — while staying *correct*:
nesting depth must never get stuck out of sync, even when a step errors.

```
▶ Loading pipeline configuration
  ├─ ℹ Reading config.yml
  ├─ ✔ Validated 12 parameters              0.03s
  └─ ✔ Done                                  0.15s
▶ Fetching articles
  ├─ ℹ Connecting to API
  ├─ ⚠ Retry 1/3 due to timeout
  ├─ ✔ Fetched 1,204 articles                4.2s
  └─ ✔ Done                                  4.4s
✖ Classification failed
  └─ Error: model timeout after 30s
```

## 2. Naming options

`logtree`, `arbor`, `canopy`, `branchlog`, `twiglog`, `cliarbor` — pick later, doesn't
block design work.

## 3. Architecture

### 3.1 Core state

A single internal environment (`the$` or `.logtree_env`) holding:

- `stack`: a list of currently-open steps, each entry `list(label, start_time, depth,
  frame, status)`
- `depth`: current nesting depth (== `length(stack)`)
- `theme`: active glyph/color config
- `sinks`: registered appenders (console always on; file/JSON optional)
- `verbosity`: minimum level to render

### 3.2 Opening a step — `log_step()`

```r
log_step <- function(msg, glyph = NULL) {
  caller <- rlang::caller_env()
  entry <- push_step(msg, frame = caller)          # depth++, print opening line
  withr_style_defer(close_step(entry$id), caller)    # on.exit(..., add = TRUE) in caller
  invisible(entry$id)
}
```

Key property: the `on.exit` handler is registered in the **caller's frame**, not
inside `log_step()` itself. That means depth is decremented automatically the moment
the calling function returns — whether it returns normally, early (`return()`), or
via an uncaught error. This is the same mechanism `cli::cli_div()` / `cli_par()` use
internally, which is why building on `cli` makes this nearly free.

**This gives 100% reliable depth tracking.** No step can ever "leak" and leave later
output mis-indented, even in scripts that error out halfway through.

### 3.3 The harder problem: was the step a success or a failure?

`on.exit()` fires on both normal and error exit, but by itself doesn't tell you
*which one happened*. Two complementary mechanisms, layered:

**Tier 1 — leaf-level status elevation (always available, no setup required).**
`log_warn()` / `log_error()` called *inside* a step (without themselves throwing)
mark the currently-open step's status as `"warning"` / `"error"` in the stack entry.
When the step closes, it renders the elevated glyph even though the function
returned normally. Covers the common case: "the step didn't crash, but something
inside it went wrong."

**Tier 2 — uncaught errors (opt-in via a top-level wrapper).**
For the case where a step's code actually throws and the error propagates up, a
single top-level `withCallingHandlers(error = ...)` is needed *somewhere* to catch
the condition and flag the deepest open step before it unwinds. Rather than requiring
this everywhere, expose one convenience wrapper the user calls once:

```r
with_logging({
  log_step("Fetching articles")
  ...
  stop("model timeout after 30s")
})
```

`with_logging()` installs the handler, runs the block, and on error: flags the
currently-open step(s) as failed (each renders `✖` as its `on.exit` fires during
unwind), prints the error message as a leaf line, and prints a run summary.

Without `with_logging()`, an uncaught error still unwinds depth correctly (Tier 1
guarantee) — it just won't retroactively paint the interrupted step red; it'll show
as e.g. dimmed/incomplete instead. Worth documenting clearly so it's not a silent gap.

### 3.3.1 Explicit override — `log_close(status = )`

Tier 1 elevation (§3.3) is a one-way ratchet: `elevate_current_step()` only ever
raises a step's status (`running < success < warning < error`), never lowers it, and
`log_success()` doesn't participate in elevation at all. So a step that hits
`log_error()` and then genuinely recovers (retries, fails over, finishes cleanly)
still renders its close line as `✖` — the glyph reflects the *worst* status seen
during the step's lifetime, not its final outcome. That's the right default (most
elevated steps really did fail), but there's no escape hatch for callers who know
better.

`log_close(id = NULL, status = NULL)` adds one: an optional `status` argument
(`"success"` / `"warning"` / `"error"`) that force-assigns the target step's status
directly — bypassing the ratchet — immediately before the existing close. Because
`id = NULL` already resolves to "nearest open step," and `log_open()` and
`log_step()` push identical stack entries, this works for both manual steps and
`log_step()`-managed (auto-closing) steps alike: calling `log_close(status =
"success")` inside a `log_step()`-managed function closes it early, right there —
the step's later automatic close (fired by `withr::defer` on frame exit) becomes a
no-op, since the stack entry is already gone by the time it runs.

### 3.4 Leaf log lines

```r
log_info(msg)      # ℹ, current depth, no new step
log_success(msg)   # ✔
log_warn(msg)       # ⚠, elevates enclosing step
log_error(msg)      # ✖, elevates enclosing step
```

### 3.5 Sub-levels & nested sections

Nesting is unbounded and needs no new API: a `log_step()` inside another `log_step()`
is a sub-level, and because each step registers its close in *its own* caller frame,
depth composes correctly to any number of levels. A pipeline function can call a
loader function that itself opens steps, and the tree indents accordingly with no
coordination between them.

```r
with_logging({
  log_step("Pipeline")            # depth 0
  log_step("Load config")         # depth 1
    log_info("Reading config.yml")
    log_success("Validated 12 params")
  # depth returns to 0 when Load config's frame exits
  log_step("Fetch articles")      # depth 1
    log_step("Warm up cache")     # depth 2
      log_info("Priming 3 shards")
    log_success("Fetched 1,204 articles")
})
```

Optional sugar: `log_section(label, expr)` — a `with_step()`-style block wrapper for
callers who prefer to make a group explicit rather than relying on frame exit. Same
machinery underneath; purely ergonomic.

**Connector / rail rendering.** Each printed line is `<rails><connector> <glyph>
<msg>`:

- `<rails>` is one column per open ancestor: `│ ` while that ancestor is still open,
  `  ` (blank) once it has closed. This is what draws the vertical spine down the
  left as depth increases.
- `<connector>` is `├─` for any child (leaf *or* sub-step header), and `└─` only on
  the line that closes a step — the close line acts as the group's corner.
- A top-level step header has no connector (bare glyph); everything nested under it
  gets `├─` / `└─`.

**Streaming constraint (important).** This is a *live* logger — lines print as they
happen, so at the moment a child is printed we don't yet know whether it's the last
child. That rules out the offline `tree` approach of deciding `├─` vs `└─` per line
after the fact. Two workable strategies:

1. **Corner-on-close (default, zero buffering):** every child prints `├─`; the `└─`
   corner is only ever the step's own close line. Simple, fully streaming, but means
   each closed step emits an explicit close line (e.g. `└─ ✔ Done  0.15s`).
2. **One-line lookahead (optional, prettier):** hold the most recent child line at
   each depth in a 1-line buffer; flush it as `├─` when a sibling follows, or as `└─`
   when the step closes. Correct corners with no separate "Done" line, at the cost of
   a tiny per-depth buffer. Worth offering as a theme/option flag once the basic
   renderer works.

Either way, alignment from §4.3 still holds: the glyph slot sits *after* the
rails+connector prefix, so message text stays column-aligned no matter how deep the
nesting goes.

## 4. Glyphs & theme

### 4.1 Default glyph set

| Meaning     | Unicode | ASCII fallback | Default color | Width |
|-------------|---------|-----------------|----------------|-------|
| step (open) | ▶       | `>`             | cyan/bold      | 1     |
| success     | ✔       | `+`             | green          | 1     |
| warning     | ⚠       | `!`             | yellow         | 1     |
| error       | ✖       | `x`             | red            | 1     |
| info        | ℹ       | `i`             | blue           | 1     |
| tree branch | `├─`    | `` `\|-` ``      | dim            | —     |
| tree end    | `└─`    | `` `\|-` ``      | dim            | —     |
| tree pipe   | `│`     | `` `\|` ``       | dim            | —     |
| elapsed     | —       | —               | dim, right-aligned | — |

The ASCII fallback uses `|` (rail) and a single `|-` for every child — branches and
the closing line alike. Keeping one connector holds the vertical `|` aligned at each
column so the spine runs continuously like Unicode's `│`/`├`/`└`, with no ragged
mixing of a distinct corner glyph. The end of a group is shown by the rail dropping
away on the next line (and by the close line's own success glyph + elapsed), not by a
separate corner character. (Deliberately *not* `+-`, `` `- ``, `\-`, or `|_` — the
first two read as disconnected, the backslash as a diagonal, and `_` sits on the
baseline where it clashes with the glyph that follows.)

`cli` already handles Unicode-capability detection and `NO_COLOR`/non-interactive
ANSI fallback, so this table maps onto `cli`'s symbol/theme system rather than being
reimplemented — the ANSI-forcing behavior worked out previously for TTY-less
contexts (e.g. piped output, Rscript batch jobs) carries over directly.

### 4.2 Customization, including emoji

Every glyph is overridable via `logtree_set_theme()`, keyed by status, each entry
taking `glyph`, `color`, and `width`:

```r
logtree_set_theme(list(
  success = list(glyph = "🎉", width = 2),
  warning = list(glyph = "⚠️",  width = 2),
  error   = list(glyph = "🔥", width = 2),
  info    = list(glyph = "💡", width = 2),
  step    = list(glyph = "🔹", width = 2)
))
```

Three built-in presets cover the common cases without hand-rolling a theme:

- `"unicode"` (default) — the table above
- `"ascii"` — plain `+ ! x i >`, width 1, safest for files/CI logs and non-UTF-8
  terminals
- `"emoji"` — opt-in, width 2, more expressive but see the portability note below

`logtree_set_theme("emoji")` swaps the whole set; passing a list on top of an active
theme overrides individual entries only.

### 4.3 Alignment — why `width` is explicit rather than measured

This is what makes "info lines always aligned" actually hold up. Glyphs render into
a **fixed-width slot**, not a slot sized by counting characters:

- Plain ASCII/Unicode symbols (`✔ ⚠ ✖ ℹ`) render as 1 terminal cell in essentially
  every font.
- Most emoji render as 2 cells — but not reliably: it depends on the terminal
  emulator, the font, and whether the emoji carries a variation selector (U+FE0F) or
  is part of a ZWJ sequence. R's `nchar()`, and even `cli::ansi_nchar()`, count
  *characters*, not *rendered terminal cells*, so neither can be trusted to get
  emoji width right automatically.

Given that, the renderer doesn't try to auto-detect width — every glyph entry
**declares its own `width`** (default 1; the emoji preset defaults to 2), and
padding is computed from that declared value. Consequences:

- Switching themes never breaks alignment, since each theme supplies correct widths
  for its own glyphs.
- Message text for `log_info()` / `log_success()` / `log_warn()` / `log_error()`
  always starts at the same column (`indent + glyph_slot_width + 1`) — changing
  themes shifts only the glyph, never where the message text begins.
- Elapsed time stays in its own fixed, right-aligned column, independent of glyph
  width.
- A custom emoji glyph is the one place a true cross-terminal guarantee isn't
  possible — the user setting a custom `glyph` is responsible for setting a matching
  `width` for their target terminal. Worth flagging prominently in
  `logtree_set_theme()`'s docs, and worth defaulting new users to `"unicode"` rather
  than `"emoji"` for that reason.

### 4.4 Rendered preview

Same three-level run rendered under each theme. Note that within a theme, every info
line's text starts at the same column and the elapsed column shares a left edge —
switching themes moves the glyph, not the text.

**`unicode` (default)** — box-drawing rails, corner-on-close:

```
▶ Pipeline
├─ ▶ Load config
│  ├─ ℹ Reading config.yml
│  └─ ✔ Validated 12 params        0.03s
├─ ▶ Fetch articles
│  ├─ ℹ Connecting to API
│  ├─ ▶ Warm up cache
│  │  ├─ ℹ Priming 3 shards
│  │  └─ ✔ Cache ready             0.20s
│  ├─ ⚠ Retry 1/3 due to timeout
│  └─ ✔ Fetched 1,204 articles     4.2s
└─ ✔ Pipeline complete             4.6s
```

**`ascii`** — safe for log files, CI, non-UTF-8 terminals. Glyph width is still 1, so
text columns land identically to `unicode`:

```
> Pipeline
|- > Load config
|  |- i Reading config.yml
|  |- + Validated 12 params        0.03s
|- > Fetch articles
|  |- i Connecting to API
|  |- > Warm up cache
|  |  |- i Priming 3 shards
|  |  |- + Cache ready             0.20s
|  |- ! Retry 1/3 due to timeout
|  |- + Fetched 1,204 articles     4.2s
|- + Pipeline complete             4.6s
```

**`emoji`** (opt-in) — status glyphs become 2-cell emoji; tree connectors stay
box-drawing. The step/node glyph defaults to `🔹` (a neutral marker); swap in `⚙️`,
`📦`, or `🔷` if you prefer via `overrides = list(step = list(glyph = "⚙️"))`. Text
starts one column later than `unicode` but stays internally aligned:

```
🔹 Pipeline
├─ 🔹 Load config
│  ├─ 💡 Reading config.yml
│  └─ ✅ Validated 12 params       0.03s
├─ 🔹 Fetch articles
│  ├─ 💡 Connecting to API
│  ├─ 🔹 Warm up cache
│  │  ├─ 💡 Priming 3 shards
│  │  └─ ✅ Cache ready            0.20s
│  ├─ ⚠️  Retry 1/3 due to timeout
│  └─ ✅ Fetched 1,204 articles    4.2s
└─ ✅ Pipeline complete            4.6s
```

> The emoji block's alignment above is *illustrative* — exact cell width is
> renderer-dependent (§4.3), which is precisely why each emoji glyph must declare its
> own `width`. On a terminal where these emoji render as 2 cells, the columns line up;
> in a proportional-font viewer they may not. This is the tradeoff that keeps
> `"unicode"` the default.

An error path, for reference (Tier-1 status elevation flips the enclosing step's
glyph even though the block returned before crashing):

```
▶ Fetch articles
├─ ℹ Connecting to API
├─ ⚠ Retry 1/3 due to timeout
└─ ✖ Failed: model timeout after 30s   30.0s
```

## 5. Proposed public API

```r
log_step(msg, glyph = NULL)     # open a step; auto-closes on frame exit
log_section(label, expr)        # optional: explicit nested block (sugar over log_step)
log_info(msg)
log_success(msg)
log_warn(msg)
log_error(msg)
with_logging(expr)              # top-level: error handler + end-of-run summary

logtree_set_theme(theme = c("unicode", "ascii", "emoji"), overrides = list())
logtree_set_verbosity(level)    # "debug" | "info" | "warn" | "error"
logtree_sink_file(path, format = c("text", "json"))
logtree_reset()                 # clear stack/state (mainly for tests / knitr re-runs)
```

## 6. Output targets (appenders)

- **Console** (default, always on) — `cli`-rendered, ANSI/Unicode-aware
- **Plain text file** — ASCII glyphs, no ANSI, same tree structure
- **NDJSON** — one line per event: `{"ts":..., "level":..., "depth":..., "label":...,
  "elapsed":..., "status":...}` for machine consumption / later aggregation
- All active sinks fan out from the same event, so console + file + JSON can run
  simultaneously

## 7. Repo & package structure (CRAN-compliant)

The repo holds more than the package — the extra files must be excluded from the
build tarball via `.Rbuildignore` so `R CMD build` produces a clean package. Files
that ship in the tarball vs. repo-only files are marked below.

```
logtree/
├── DESCRIPTION                # ships — see §8.1
├── NAMESPACE                  # ships — roxygen2-generated, do not hand-edit
├── LICENSE                    # ships — MIT: two lines, YEAR + COPYRIGHT HOLDER
├── LICENSE.md                 # repo-only (.Rbuildignore) — full licence text
├── R/
│   ├── logtree-package.R      # package-level doc (@keywords internal "_PACKAGE")
│   ├── state.R                # internal env, stack push/pop
│   ├── step.R                 # log_step(), close_step(), on.exit machinery
│   ├── section.R              # log_section() block sugar
│   ├── leaves.R              # log_info/success/warn/error, status elevation
│   ├── theme.R                # glyph sets, colors, cli theme integration
│   ├── glyphs.R               # glyph tables as \u escapes (see §8.2)
│   ├── appenders.R            # console/file/json sinks
│   ├── run.R                  # with_logging(), summary printing
│   └── zzz.R                  # .onLoad/.onAttach (no printing on load)
├── man/                       # ships — roxygen2-generated Rd; every export documented
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── test-depth-tracking.R     # esp. error-unwind cases
│       ├── test-status-elevation.R
│       ├── test-rendering.R          # snapshot tests w/ frozen clock (§8.4)
│       └── test-appenders.R
├── vignettes/
│   └── logtree.Rmd            # ships — must build fast, no internet
├── inst/
│   └── CITATION               # optional
├── README.Rmd                 # repo-only (.Rbuildignore)
├── README.md                  # ships — rendered from README.Rmd
├── .Rbuildignore              # excludes README.Rmd, ^\.github$, ^pkgdown$, design doc, etc.
├── .github/                   # repo-only — R-CMD-check GitHub Action
├── pkgdown/                   # repo-only
└── logtree-design-doc.md      # repo-only (this document)
```

## 8. CRAN compliance

Target: `R CMD check --as-cran` with **0 errors, 0 warnings, 0 notes**. The
non-obvious, *package-specific* pitfalls (beyond generic hygiene) are below.

### 8.1 DESCRIPTION

- `Title`: title case, no trailing period, ≤ 65 chars (e.g. "Tree-Style Process
  Logging for the Console").
- `Description`: one or more full sentences; must **not** start with the package name,
  "This package", or "A package". Wrap `cli` in single quotes as a package reference.
- `Authors@R` with `person(..., role = c("aut", "cre"))`; ORCID optional.
- `License: MIT + file LICENSE` (and the two-line `LICENSE` file).
- `Imports: cli, rlang` — both on CRAN, so fine. Nothing goes in `Depends`.
- `Encoding: UTF-8`. Add `Roxygen` and `RoxygenNote` fields.

### 8.2 Non-ASCII glyphs — the biggest gotcha here

CRAN's portability rule: **package R source should contain only ASCII**; non-ASCII
must be given as `\u` escapes, not literal characters. That directly hits this
package, whose whole point is box-drawing and emoji glyphs. So the glyph tables in
`glyphs.R` are defined as escapes, never literals:

```r
# ✔  →  "\u2714"      ✖ → "\u2716"      ⚠ → "\u26a0"      ℹ → "\u2139"
# ▶  →  "\u25b6"      ├ → "\u251c"      ─ → "\u2500"      │ → "\u2502"   └ → "\u2514"
glyphs_unicode <- list(
  success = list(glyph = "\u2714", width = 1L),
  error   = list(glyph = "\u2716", width = 1L),
  warning = list(glyph = "\u26a0", width = 1L),
  info    = list(glyph = "\u2139", width = 1L),
  step    = list(glyph = "\u25b6", width = 1L)
)
```

Emoji likewise as `\U` escapes (e.g. `"\U0001f539"` for the 🔹 step node). Prefer building tree
connectors from `cli::symbols` / `cli::tree()` where possible, which sidesteps hard
-coding some of these. Keep examples and vignettes ASCII too, or gate non-ASCII demo
output behind `\donttest{}`.

### 8.3 Global state & side effects

- The package-private environment (§3.1) is fine — CRAN objects to writing to the
  *global* env or the user's home dir, not to a package-internal env.
- Side-effecting functions (`log_*`, `logtree_*`) must `return(invisible(...))`.
- **Never** print on load. Use `.onAttach()` + `packageStartupMessage()` for any
  banner (and ideally none). Diagnostics go to `stderr` via `message()`/`cli`, not
  `cat()` to stdout.
- Anything that touches `options()` or console state must restore it on exit
  (`on.exit()` or `withr::defer()`); don't leave global options mutated.
- File appenders in **examples** must write only to `tempfile()`/`tempdir()`, never
  the working dir or `~`.

### 8.4 Tests & examples

- Reset internal state between tests via `logtree_reset()` (in a `withr::defer()` or
  `test_that` teardown) so a leaked stack from one test can't corrupt the next.
- Elapsed times are non-deterministic → snapshot tests (`testthat::expect_snapshot`)
  must use a **frozen/mock clock** (inject the time source, or `withr::with_options`)
  so the tree renders identically every run.
- No internet in tests/examples/vignettes (CRAN runs offline).
- Every example runs in < 5s; wrap anything slower in `\donttest{}` (not
  `\dontrun{}`, which CRAN discourages unless truly unrunnable).

### 8.5 Documentation & NAMESPACE

- roxygen2 with explicit `@importFrom cli ...` / `@importFrom rlang caller_env` — no
  wholesale `@import`. `NAMESPACE` exports only the public API from §5.
- Every exported function needs `@return` (CRAN now checks for missing value docs)
  and at least one runnable `@examples` block.
- Ship a package-level help page (`?logtree`) via `logtree-package.R`.

## 9. Open questions / deferred scope

- **Parallel workers** (`furrr`/`parallel`): out of scope for v1 per current
  decision; global stack assumption breaks across processes. Future path: scope
  state by `Sys.getpid()` and merge logs post-hoc, or require each worker to own an
  explicit logger object (the alternative model considered and set aside earlier).
- **Very deep nesting**: may get visually noisy; consider an optional max-depth
  collapse or `verbosity`-based pruning.
- **Default summary behavior**: should `with_logging()` always print an end-of-run
  summary (counts of ok/warn/error steps, total time), or only when requested?
- **Emoji width portability**: declared `width` values are a best-effort convention,
  not a guarantee — a custom emoji glyph can still misalign on a terminal/font
  combination it wasn't tuned for. No general fix beyond documenting it clearly and
  defaulting to `"unicode"`.

## 10. Suggested build order

1. Package skeleton via `usethis::create_package()` + `use_mit_license()`,
   `use_testthat()`, `use_roxygen_md()` — start CRAN-clean rather than retrofitting.
2. Internal stack + `on.exit` depth tracking, plain-text ASCII output only — prove
   correctness first, especially the error-unwind case, before any visual polish.
3. Glyph tables as `\u` escapes (§8.2) + colors via `cli`, tree connector rendering.
4. Leaf functions + status elevation logic.
5. Timing + elapsed-time display (with an injectable clock for testable snapshots).
6. `with_logging()` top-level handler + run summary.
7. File / NDJSON appenders (tempdir-only in examples).
8. Docs, vignette, README.Rmd, tests; run `R CMD check --as-cran` and drive it to
   0/0/0 before considering a submission.
