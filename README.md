
<!-- README.md is generated from README.Rmd. Please edit that file -->

# logtree <a href="https://ivansortino.github.io/logtree/"><img src="man/figures/logo.png" align="right" height="139" alt="logtree website" /></a>

<!-- badges: start -->

[![R-CMD-check](https://github.com/IvanSortino/logtree/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/IvanSortino/logtree/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/IvanSortino/logtree/graph/badge.svg)](https://app.codecov.io/gh/IvanSortino/logtree)

[Documentation](https://IvanSortino.github.io/logtree/) \|
[GitHub](https://github.com/IvanSortino/logtree)

<!-- badges: end -->

logtree renders nested process execution as a live, colored tree in the
console – tree connectors, status glyphs, and elapsed time per step –
while keeping nesting depth correct even when a step errors partway
through.

<p align="center">

<img src="man/figures/README-tree-color.svg" alt="Annotated logtree console output" width="760" />
</p>

## Installation

Install the development version from
[GitHub](https://github.com/IvanSortino/logtree):

``` r
# install.packages("pak")
pak::pak("IvanSortino/logtree")
```

Or install directly from CRAN:

``` r
install.packages("logtree")
```

## Quick start

``` r
library(logtree)

pipeline <- function() {
  log_step("Pipeline")
  load_config()
}

load_config <- function() {
  log_step("Load config")
  log_info("Reading config.yml")
  log_success("Validated 12 parameters")
}

pipeline()
#> ▶ Pipeline
#> ├─ ▶ Load config
#> │  ├─ ℹ Reading config.yml
#> │  ├─ ✔ Validated 12 parameters
#> │  └─ ✔ Done  0.00s
#> └─ ✔ Done  0.01s
logtree_summary()
#> 
#> ── Summary: nothing to report ──────────────────────────────────────────────────
```

`log_step()` is meant to be called from inside a function: the step
auto-closes when the function that opened it returns – normally, early,
or via an uncaught error – so nesting depth never gets stuck out of
sync. (At top level, with no function frame to close on, reach for
`log_open()` / `log_close()` instead.)

## Status levels & verbosity

Five leaf levels – `log_debug()`, `log_info()`, `log_success()`,
`log_warn()`, `log_error()` – plus `logtree_threshold()` to filter them.
`log_warn()`/ `log_error()` also elevate the enclosing step’s glyph,
even when hidden by verbosity; step lines always render regardless of
threshold.

``` r
fetch <- function() {
  log_step("Fetch")
  log_debug("cache miss for key user:42")
  log_info("requesting from API")
  log_warn("rate limit at 80%")
  log_success("fetched 128 rows")
}

with_logging(fetch(), summary = FALSE) # default verbosity ("info"): debug hidden
#> ▶ Fetch
#> ├─ ℹ requesting from API
#> ├─ ⚠ rate limit at 80%
#> ├─ ✔ fetched 128 rows
#> └─ ⚠ Done  0.00s

logtree_threshold("debug")
with_logging(fetch(), summary = FALSE) # verbosity raised: debug shown
#> ▶ Fetch
#> ├─ ⚙ cache miss for key user:42
#> ├─ ℹ requesting from API
#> ├─ ⚠ rate limit at 80%
#> ├─ ✔ fetched 128 rows
#> └─ ⚠ Done  0.00s
logtree_threshold("info")
```

## Error handling

When a step actually throws, `with_logging()` marks every currently-open
step failed, logs the condition as a leaf, prints a run summary, then
rethrows – it never silently swallows errors.

``` r
apply_migration <- function() {
  log_step("Apply migration")
  log_info("adding column users.tier")
  stop("constraint violation on users.email")
}

try(with_logging(apply_migration()), silent = TRUE)
#> ▶ Apply migration
#> ├─ ℹ adding column users.tier
#> ├─ ✖ constraint violation on users.email
#> └─ ✖ Done  0.00s
#> ✖ Run failed in 0.00s
```

A `log_error()` from code that returns normally is softer: it elevates
the enclosing step’s glyph but lets the run continue, and
`log_close(status = "success")` overrides it once you know recovery
worked.

## Run summary

`logtree_summary()` prints a breadcrumb digest of every error, warning,
and pinned leaf since the last reset – so you see *what* went wrong
without scrolling back through the tree. `filter` restricts by status,
`depth` trims each breadcrumb to its `N` deepest nodes.

``` r
logtree_reset()

migrate <- function() {
  log_step("Apply migration")
  log_warn("table lock held 800ms")
  log_error("constraint violation on users.email")
}

release <- function() {
  log_step("Release v2.1")
  migrate()
  log_step("Smoke test")
  log_success("all endpoints 200")
}

with_logging(release(), summary = FALSE)
#> ▶ Release v2.1
#> ├─ ▶ Apply migration
#> │  ├─ ⚠ table lock held 800ms
#> │  ├─ ✖ constraint violation on users.email
#> │  └─ ✖ Done  0.00s
#> ├─ ▶ Smoke test
#> │  ├─ ✔ all endpoints 200
#> │  └─ ✔ Done  0.00s
#> └─ ✔ Done  0.00s
logtree_summary()
#> 
#> ── Summary: 1 error, 1 warning ─────────────────────────────────────────────────
#> ⚠ Release v2.1 › Apply migration › table lock held 800ms
#> ✖ Release v2.1 › Apply migration › constraint violation on users.email
```

## Call sites

The digest tells you *what* went wrong; the `trace` theme slot tells you
*where*. It is off by default – `show = "problems"` annotates warnings,
errors and interrupted steps, which is usually all you want:

``` r
logtree_reset()
logtree_theme(list(trace = list(show = "problems", format = "{fn}()")))

parse_rows <- function() {
  log_step("Parse rows")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}

load_data <- function() {
  log_step("Load data")
  parse_rows()
}

with_logging(load_data(), summary = FALSE)
#> ▶ Load data
#> ├─ ▶ Parse rows
#> │  ├─ ℹ 1200 rows
#> │  ├─ ⚠ coerced 3 rows  parse_rows()
#> │  └─ ⚠ Done  0.00s
#> └─ ✔ Done  0.00s
logtree_summary()
#> 
#> ── Summary: 1 warning ──────────────────────────────────────────────────────────
#> ⚠ Load data › Parse rows › coerced 3 rows  parse_rows()
```

The column is a template over `{fn}`, `{file}` and `{line}`, defaulting
to `"{file}:{line} {fn}()"` – in a real script (where source references
exist, unlike this README’s knitted chunks) it reads:

    ▶ Load data  R/pipeline.R:12 load_data()
    ├─ ▶ Parse rows  R/pipeline.R:18 parse_rows()
    │  ├─ ⚠ coerced 3 rows  R/pipeline.R:20 parse_rows()

The location is a terminal hyperlink – click it and your editor opens at
that line. `show` also takes the statuses themselves, and file sinks and
the digest can carry call sites while the console stays quiet. See
[`?logtree_theme`](https://IvanSortino.github.io/logtree/reference/logtree_theme.html)
for the full set of options.

## Grouping

Adjacent `log_step()` calls that share a `group = c(name = value)` value
collapse under one `< name >` header instead of stacking as siblings:

``` r
check <- function(item, label) {
  log_step(label, group = stats::setNames(item, paste0("Item ", item)))
  log_info(paste0(label, " running"))
  log_success(paste0(label, " ok"))
}

process_item <- function(item) {
  check(item, "validate schema")
  check(item, "check bounds")
}

run_pipeline <- function() {
  log_step("Pipeline run")
  for (i in 1:2) process_item(i)
}

with_logging(run_pipeline(), summary = FALSE)
#> ▶ Pipeline run
#> ├─ ▣ Item 1
#> │  ├─ ▶ validate schema
#> │  │  ├─ ℹ validate schema running
#> │  │  ├─ ✔ validate schema ok
#> │  │  └─ ✔ Done  0.00s
#> │  ├─ ▶ check bounds
#> │  │  ├─ ℹ check bounds running
#> │  │  ├─ ✔ check bounds ok
#> │  │  └─ ✔ Done  0.00s
#> │  └─ ✔ Done  0.00s
#> ├─ ▣ Item 2
#> │  ├─ ▶ validate schema
#> │  │  ├─ ℹ validate schema running
#> │  │  ├─ ✔ validate schema ok
#> │  │  └─ ✔ Done  0.00s
#> │  ├─ ▶ check bounds
#> │  │  ├─ ℹ check bounds running
#> │  │  ├─ ✔ check bounds ok
#> │  │  └─ ✔ Done  0.00s
#> │  └─ ✔ Done  0.00s
#> └─ ✔ Done  0.00s
```

## Themes

`logtree_theme()` swaps the whole glyph/color preset – `"unicode"`,
`"ascii"`, `"emoji"`, `"minimal"`, `"ci"`:

``` r
demo_build <- function() {
  with_logging({
    log_step("Build")
    log_info("compiling")
    log_warn("3 deprecation warnings")
    log_success("build ok")
  }, summary = FALSE)
}

logtree_theme("ascii")
demo_build()
#> > Build
#> |- i compiling
#> |- ! 3 deprecation warnings
#> |- + build ok
#> |- ! Done  0.00s

logtree_theme("emoji")
demo_build()
#> 🔹 Build
#> ├─ 💡 compiling
#> ├─ ⚠️ 3 deprecation warnings
#> ├─ ✅ build ok
#> └─ ⚠️ Done  0.00s

logtree_theme("unicode")
```

Any preset can be tuned: `overrides` restyles individual slots (glyph,
color, brackets), while `compact` and `glyph_gap` tighten the tree’s
horizontal spacing.

``` r
logtree_theme("unicode",
  overrides = list(success = list(glyph = "*", color = c("green", "bold"))),
  compact = "medium"
)
demo_build()
#> ▶ Build
#> ├─ℹ compiling
#> ├─⚠ 3 deprecation warnings
#> ├─* build ok
#> └─⚠ Done  0.00s
logtree_theme("unicode")
```

The full list of slots and fields is in the [Themes section of the
vignette](https://IvanSortino.github.io/logtree/articles/logtree.html#themes)
and `?logtree_theme`.

## More

- **Output sinks** –
  `logtree_sink_file(path, format = c("text", "json"))` mirrors console
  output to a plain-text or NDJSON file; every registered sink runs
  alongside the console sink.
- **`logger` integration** – `logtree_logger()` routes the
  [logger](https://daroczig.github.io/logger/) package through logtree
  in one call, so `logger::log_info()` and friends render as logtree
  leaves.
- **Manual step control** – `log_open()`/`log_close()` open and close
  steps by hand instead of relying on frame exit, useful at top level or
  across script blocks.
- **Re-running top-level lines** – re-running the same line in
  RStudio/Positron re-anchors to the same node instead of nesting deeper
  on every run.

See `vignette("logtree")` and the [documentation
site](https://IvanSortino.github.io/logtree/) for full details on error
handling semantics, manual step control, and the design philosophy
behind the tree renderer.
