# logtree feature plan

Implementation plans for the features brainstormed alongside the theme work but
**not built yet**. Five siblings of these already shipped -- themeable close
text, the `elapsed` slot, the `minimal` and `ci` presets, and message wrapping
-- so the patterns they established are the ones to follow here.

Repo-only, like `logtree-design-doc.md`; `debug/` is already in `.Rbuildignore`.
Consult the design doc for the *why* behind anything referenced below.

**Ordering.** Roughly by payoff over cost. Items 1-3 are additive and
low-risk. Items 4-6 rework the sink layer and are best done together, in that
order. Items 7-8 are small but touch condition handling, which is the part of
the package most able to break quietly.

| # | Feature | Size | Risk | Public API added |
| - | ------- | ---- | ---- | ---------------- |
| 1 | Block form `log_section()` | S | low | 1 fn |
| 2 | Structured fields on leaves | M | medium | 5 fns changed |
| 3 | Timestamp column | S | low | 1 theme slot |
| 4 | `logtree_sink()` + sink removal | M | medium | 3 fns |
| 5 | Memory sink | S | low | 1 fn |
| 6 | Per-sink threshold + richer JSON | M | medium | args on 2 fns |
| 7 | `with_logging(warnings = TRUE)` | S | medium | 1 arg |
| 8 | Mute switch | S | low | 1 fn + 1 option |

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

---

## 3. Timestamp column

**Problem.** A live tree shows elapsed time per step but never wall-clock time,
so a log read after the fact cannot be lined up against anything else.

**Proposed API.**

```r
logtree_theme(list(timestamp = list(format = "%H:%M:%S", color = "silver")))
#> 14:22:07 ▶ Pipeline
```

A new `timestamp` theme slot: `format` (a `strftime` format, `NULL` = off),
`color`.

**Implementation.** Prefix the timestamp *before* the rails, in the same place
for every line kind. The natural home is `compose_line()` (`R/step.R`), which
already assembles every tree line -- prepend there and every kind gets it for
free, including wrapped continuations.

**Design risks.**
- **It must be fixed-width or the tree shears.** `%H:%M:%S` is stable, but a
  user format need not be. Render once, measure with `cli::ansi_nchar()`, and
  pad or truncate every line to that width. Compute the width from a *sample*
  timestamp at render time rather than trusting the format string.
- `cols` in `compose_line()` must include the timestamp width, or wrapping will
  overflow by exactly that much.
- Continuation lines need a blank timestamp column, not a repeated timestamp.
- File sinks: a text sink probably *does* want timestamps even though it
  renders through `glyphs_ascii`. Either give `glyphs_ascii` a default format
  or add a `timestamp` argument to `logtree_sink_file()`. Decide deliberately.

**Tests.** Fixed-width padding with a variable-width format; alignment against
a no-timestamp render; wrapping with a timestamp; continuation column blank.

---

## 4. `logtree_sink()` and sink removal

**Problem.** `the$sinks` only ever grows. `logtree_sink_file()` is the only way
to add one, there is no way to add a custom one, and no way to remove any --
`logtree_reset()` deliberately does not clear sinks. A test that adds a sink
leaks it into every later test in the same session; `helper-sinks.R` exists
purely to work around this by restoring `list(console_sink)` by hand.

**Proposed API.**

```r
h <- logtree_sink(function(event) { ... })   # returns a handle
logtree_sink_remove(h)
logtree_sinks()                              # list active handles
```

`logtree_sink_file()` returns a handle too (currently `NULL`), which is
backward-compatible since nothing can be relying on an invisible `NULL`.

**Implementation.** Change `the$sinks` from an unnamed list to a list keyed by
id, with a `the$next_sink_id` counter alongside `the$next_id` in `R/state.R`.
`emit()` iterates values, so it is unaffected. Keep the console sink under a
reserved id so `logtree_sink_remove()` can target it -- turning the console off
is a real use case for a library author.

**Design risks.**
- Ordering: sinks must fire in registration order. A named list preserves it;
  do not switch to an environment.
- Whether `logtree_reset()` should now clear sinks. It should *not* -- the
  current split (sinks survive reset, summary does not) is deliberate and
  documented. Add `logtree_sink_remove()` as the explicit path instead.
- A user sink that throws will break `emit()` mid-fanout, leaving later sinks
  unwritten. Wrap each call in `tryCatch()` and warn once per sink, or the
  logger becomes a source of errors rather than a witness to them.

**Tests.** Add/remove/list; ordering preserved; removing the console sink;
a throwing sink does not stop the others.

---

## 5. Memory sink

**Problem.** There is no way to assert on your own logging. Testing that a
pipeline logged what it should means capturing console output and pattern
matching it.

**Proposed API.**

```r
h <- logtree_sink_memory()
run_pipeline()
events <- logtree_sink_memory_events(h)   # data.frame, one row per event
```

**Implementation.** Trivial once item 4 exists: a closure over an environment
accumulating events, plus a reader. Columns mirror `to_json_line()`'s schema
(`ts`, `level`, `id`, `parent_id`, `depth`, `label`, `elapsed`, `status`) so
the memory sink and the JSON sink agree.

**Design risks.** Unbounded growth in a long run -- take a `max` argument and
keep the last N, or document it as test-only. Prefer the cap.

**Tests.** Event shape matches the JSON schema; ordering; cap behaviour.

---

## 6. Per-sink threshold and richer JSON

**Problem.** `logtree_threshold()` is global, so a debug-level file sink forces
debug onto the console too. Separately, the JSON sink drops everything except
`label` -- no run id, and `ts` is a bare `as.numeric(Sys.time())` rather than
anything a log aggregator can parse.

**Proposed API.**

```r
logtree_sink_file(path, format = "json", threshold = "debug")
```

**Implementation.**
- Threshold: `should_emit_leaf()` currently gates inside `emit_leaf()`, *before*
  the fanout, so a suppressed leaf never reaches any sink. Per-sink gating means
  moving the decision into the fanout: always emit, and let each sink decide.
  The console sink takes the global threshold as its default.
- **This is a real behaviour change**: `emit_leaf()`'s gate also currently
  suppresses `record_summary()`. Moving it must not start recording suppressed
  leaves in the digest -- or must deliberately start doing so. Decide and test.
- JSON: add ISO-8601 `ts` (`format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")`), a
  run id generated per `with_logging()` call or per session, and item 2's
  fields. Keep the hand-rolled encoder; the shape is still small and fixed.

**Design risks.** The gating move is the risky part -- it changes when
`record_summary()` sees an event. Write the summary tests first.

---

## 7. `with_logging(warnings = TRUE)`

**Problem.** Tier-2 handling catches `error` only. An R `warning()` or
`message()` raised by wrapped code goes to stderr, outside the tree, while a
`log_warn()` call renders inside it. Same severity, two different places.

**Proposed API.** `with_logging(expr, warnings = TRUE)` routes `warning()` and
`message()` conditions from wrapped code into `log_warn()` / `log_info()`
leaves.

**Implementation.** The same `withCallingHandlers()` already installed in
`with_logging()` (`R/run.R`) gains `warning =` and `message =` handlers that
call `log_warn(conditionMessage(cnd))` and then `invokeRestart("muffleWarning")`
/ `invokeRestart("muffleMessage")`.

**Design risks.**
- **Muffling is the decision, not the plumbing.** Muffling means the warning no
  longer reaches `warnings()` or the user's own handlers. Not muffling means it
  appears twice. Recommend muffling, since the tree is then the single record,
  but it must be opt-in (which `warnings = TRUE` is) and loudly documented.
- `log_warn()` elevates the enclosing step's status. That is right for a real
  `warning()`, but it means wrapping noisy third-party code turns every step
  yellow. Mention it in the docs.
- Do not route into the `global = TRUE` handler without separate thought:
  a session-persistent warning handler would capture warnings from unrelated
  code, which is exactly the trap `global_error_action()`'s stack-empty guard
  exists to avoid. Apply the same guard.

**Tests.** Warning and message routed as leaves; step elevation; muffling;
`warnings = FALSE` (the default) unchanged; interaction with the error handler.

---

## 8. Mute switch

**Problem.** A library author who logs with logtree has no way to silence it in
their own test suite short of unregistering sinks, and there is currently no way
to unregister (item 4).

**Proposed API.**

```r
logtree_mute()                     # or options(logtree.silent = TRUE)
logtree_unmute()
```

**Implementation.** A `the$muted` flag checked at the top of `emit()`. Cheaper
and more predictable than removing sinks, and it survives `logtree_reset()`
consistently with sinks.

**Design risks.**
- **Does muting stop `record_summary()` too?** It should not: the digest is a
  record, not output, and a muted run should still be able to report what went
  wrong at the end. Check the flag *after* `record_summary()` in `emit()`, not
  before.
- Precedence between the option and the function call: let the function win and
  read the option only at `.onLoad`, matching how `the$verbosity` is
  initialised (`R/zzz.R`).
- Muting must not affect step *bookkeeping* -- the stack still has to push and
  pop, or depth desyncs the moment logging is turned back on.

**Tests.** Muted run prints nothing; summary still records; unmute restores;
stack depth correct across a mute/unmute cycle.
