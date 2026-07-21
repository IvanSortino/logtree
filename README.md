
<!-- README.md is generated from README.Rmd. Please edit that file -->

# logtree

<!-- badges: start -->

[Documentation](https://IvanSortino.github.io/logtree/) \|
[GitHub](https://github.com/IvanSortino/logtree)

<!-- badges: end -->

logtree renders nested process execution as a live, colored tree in the
console – tree connectors, status glyphs, and elapsed time per step –
while keeping nesting depth correct even when a step errors partway
through.

    > Loading pipeline configuration
      |- i Reading config.yml
      |- + Validated 12 parameters              0.03s
      |- + Done                                  0.15s
    > Fetching articles
      |- i Connecting to API
      |- ! Retry 1/3 due to timeout
      |- + Fetched 1,204 articles                4.2s
      |- + Done                                  4.4s
    x Classification failed
      |- Error: model timeout after 30s

## Installation

logtree isn’t on CRAN yet. Install the development version from
[GitHub](https://github.com/IvanSortino/logtree):

``` r
# install.packages("pak")
pak::pak("IvanSortino/logtree")
```

Once released to CRAN:

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
#> └─ ✔ Done  0.00s
```

Steps auto-close when the function that opened them returns – normally,
early, or via an uncaught error – so nesting depth never gets stuck out
of sync.

## Status levels & verbosity

Five leaf levels – `log_debug()`, `log_info()`, `log_success()`,
`log_warn()`, `log_error()` – plus `logtree_threshold()` to filter them.
`log_warn()`/ `log_error()` also elevate the enclosing step’s glyph,
even when suppressed by verbosity; step lines always render regardless
of threshold.

``` r
fetch <- function() {
  log_step("Fetch")
  log_debug("cache miss for key user:42")
  log_info("requesting from API")
  log_warn("rate limit at 80%")
  log_success("fetched 128 rows")
}

logtree_reset()
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

`log_error()` from code that itself returns normally elevates the
enclosing step’s glyph but lets the run continue – pass
`status = "success"` to `log_close()` once you know recovery actually
worked:

``` r
connect_db <- function() {
  log_step("Connect primary")
  log_error("primary unreachable")
  log_info("failing over to replica")
  log_success("connected to replica")
  log_close(status = "success") # recovered: override the elevated glyph
}

logtree_reset()
with_logging(connect_db(), summary = FALSE)
#> ▶ Connect primary
#> ├─ ✖ primary unreachable
#> ├─ ℹ failing over to replica
#> ├─ ✔ connected to replica
#> └─ ✔ Done  0.00s
```

A step whose code actually throws is different: `with_logging()` marks
every currently-open step failed, logs the condition as a leaf, prints a
run summary, then rethrows – it never silently swallows errors.

``` r
apply_migration <- function() {
  log_step("Apply migration")
  log_info("adding column users.tier")
  stop("constraint violation on users.email")
}

logtree_reset()
try(with_logging(apply_migration()), silent = TRUE)
#> ▶ Apply migration
#> ├─ ℹ adding column users.tier
#> ├─ ✖ constraint violation on users.email
#> └─ ✖ Done  0.00s
#> ✖ Run failed in 0.00s
```

## Grouping

Adjacent `log_step()` calls that share a `group_by = c(name = value)`
value collapse under one `< name >` header instead of stacking as
siblings:

``` r
check <- function(item, label) {
  log_step(label, group_by = stats::setNames(item, paste0("Item ", item)))
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

logtree_reset()
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
#> ├─ ▣ Item 2
#> │  ├─ ▶ validate schema
#> │  │  ├─ ℹ validate schema running
#> │  │  ├─ ✔ validate schema ok
#> │  │  └─ ✔ Done  0.00s
#> │  ├─ ▶ check bounds
#> │  │  ├─ ℹ check bounds running
#> │  │  ├─ ✔ check bounds ok
#> │  │  └─ ✔ Done  0.00s
#> └─ ✔ Done  0.00s
```

## Themes

`logtree_theme()` swaps the whole glyph/color preset (`"unicode"`,
`"ascii"`, `"emoji"`) or merges per-glyph overrides onto the active one:

``` r
demo_build <- function() {
  logtree_reset()
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
demo_build()
#> ▶ Build
#> ├─ ℹ compiling
#> ├─ ⚠ 3 deprecation warnings
#> ├─ ✔ build ok
#> └─ ⚠ Done  0.00s
```

## More

- **Output sinks** –
  `logtree_sink_file(path, format = c("text", "json"))` mirrors console
  output to a plain-text or NDJSON file; every registered sink runs
  alongside the console sink.
- **`logger` integration** – `layout_logtree()` bridges the
  [logger](https://daroczig.github.io/logger/) package so
  `logger::log_info()` and friends render as logtree leaves.
- **Manual step control** – `log_open()`/`log_close()` open and close
  steps by hand (with an explicit `parent`) instead of relying on frame
  exit, useful at top level or across script blocks.

See `vignette("logtree")` and the [documentation
site](https://IvanSortino.github.io/logtree/) for full details on error
handling semantics, manual step control, and the design philosophy
behind the tree renderer.
