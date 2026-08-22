# logtree feature plan

Implementation plans for the features brainstormed alongside the theme work but
**not built yet**. The other six of the original eight have since shipped --
the timestamp column, the sink registry (`logtree_sink()` / `logtree_sinks()` /
`logtree_sink_remove()`), the memory sink, per-sink thresholds with a richer
JSON record, `with_logging(warnings = )`, and the mute switch -- so the
patterns *they* established are the ones to follow here, alongside the five
older siblings (themeable close text, the `elapsed` slot, the `minimal` and
`ci` presets, message wrapping).

Repo-only, like `logtree-design-doc.md`; `debug/` is already in `.Rbuildignore`.
Consult the design doc for the *why* behind anything referenced below.

**Ordering.** Item 1 is additive and low-risk. Item 2 changes the shape of a
leaf event, which every sink and the JSON encoder read, so it wants doing
carefully.

| # | Feature | Size | Risk | Public API added |
| - | ------- | ---- | ---- | ---------------- |
| 1 | Block form `log_section()` | S | low | 1 fn |
| 2 | Structured fields on leaves | M | medium | 5 fns changed |

---

## 1. Block form: `log_section(label, expr)`

**Problem.** `log_step()` hangs its close on the *caller's* frame exiting. At
top level there is no such frame, so the step never closes -- `log_step()`
prints a one-time nudge about exactly this (`R/step.R`, the `globalenv()`
branch). The manual `log_open()` / `log_close()` pair works but has to be kept
balanced by hand, and an error between them leaks the step unless something
else unwinds it.

**Proposed API.**

```r
log_section("Load data", {
  log_info("reading config.yml")
  read_csv(path)
})                       # returns the block's value, invisibly
```

Scoped like `withr::with_*`: opens the step, evaluates `expr`, closes on exit
whatever happens, returns the value.

**Implementation.** New `R/section.R`.

```r
log_section <- function(label, expr, glyph = NULL, parent = NULL,
                        group = NULL, status = NULL) {
  entry <- push_step(label, glyph, group = group, parent = parent)
  on.exit(close_step(entry$id), add = TRUE)
  force(expr)            # lazily evaluated, so it runs inside the step
}
```

The close belongs on `log_section()`'s *own* frame -- unlike `log_step()`,
which must defer into the caller's. `on.exit()` fires on an error too, so
`finalize_step()`'s interrupted-status logic must be reachable from here; reuse
`finalize_step()` rather than calling `close_step()` directly, so an error
inside the block still renders the dimmed glyph rather than a false success.

**Design risks.**
- `expr` must be a promise, not pre-evaluated -- the argument order matters, and
  `force()` has to happen *after* `push_step()` or the block's own log lines
  land outside the step.
- Nesting inside `log_step()` must still work: `push_step()` reads
  `current_depth()`, so it does, but test it explicitly.
- Return-value semantics: return `expr`'s value, not the step id. That differs
  from `log_step()`/`log_open()`, which return ids -- document the difference.

**Tests.** Value passthrough; close on normal return, on `return()` from an
enclosing function, and on error; correct depth when nested in `log_step()`;
top-level use emits no nudge (this is the fix for it).

**Also.** Update `log_step()`'s top-level nudge to point at `log_section()`
first and `log_open()` second, since the block form is the better answer.

---

## 2. Structured fields on leaves

**Problem.** A leaf carries a single pre-formatted string. Callers end up doing
`log_info(sprintf("loaded %d rows from %s", n, f))`, which reads fine on the
console but reaches the JSON sink as an opaque sentence -- `to_json_line()`
(`R/appenders.R`) has no field to put `n` or `f` in. The structure the caller
already had is thrown away at the call site.

**Proposed API.**

```r
log_info("Loaded", n = 12, file = "x.csv")
#> ├─ ℹ Loaded  n=12 file=x.csv        (dim, after the message)
```

`...` on all five leaf functions, captured as a named list.

**Implementation.**
- `emit_leaf()` gains `fields`; the event gains a `fields` element.
- Rendering: a new `fields` theme slot (`color`, `sep`, `format`) so the
  key=value tail is styleable and can be turned off. Format it in
  `format_leaf()` *after* the message, and make it part of the wrappable text
  so `wrap` keeps working.
- `to_json_line()` emits them as real JSON keys. This is where the value is.
  Note the record is shared now: `event_record()` flattens an event once for
  both the JSON sink and the memory sink, with the column set declared in
  `record_proto()` (`R/appenders.R`). Fields have to reach both, or the two
  views of a run start disagreeing -- which is precisely what that refactor
  exists to prevent.

**Design risks.**
- **Name collisions with existing arguments.** `log_info(msg, close, summary)`
  already has three named parameters, so `log_info("x", close = 1)` would be
  ambiguous. Put `...` *after* them and document that those three names are
  reserved; or, safer, take an explicit `fields = list(...)` argument and skip
  `...` entirely. Recommend the explicit list: it is uglier at the call site but
  cannot silently swallow a typo'd `closr = TRUE`.
- The hand-rolled JSON encoder (`json_scalar()`) handles scalars only. Fields
  must be validated as length-1 atomics, or the encoder needs a vector case.
- Non-scalar or `NULL` field values need a defined rendering.

**Tests.** Console rendering with and without fields; wrapping interaction;
JSON round-trip through `jsonlite::fromJSON()` (a Suggests dependency, so guard
with `skip_if_not_installed()`); reserved-name collision behaviour.
