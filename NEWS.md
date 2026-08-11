# logtree (development version)

## Breaking changes

* NDJSON schema: a `"json"` sink's `ts` is now ISO-8601 to the millisecond with a
  UTC offset (`"2026-01-02T03:04:05.000+0000"`) instead of a bare epoch number,
  and every record carries a `run_id` so one run can be picked out of a shared
  file. The id is derived from the wall clock, the pid and a session counter, so
  it never perturbs the RNG stream; it is refreshed per `with_logging()` call and
  per `logtree_reset()`.

* Verbosity is now a *rendering* gate only. A warning suppressed by
  `logtree_threshold("error")` still reaches the `logtree_summary()` digest (it
  already elevated its step's close glyph). `summary = TRUE`/`FALSE` still pin and
  exclude a line as before.

## Sinks

* New sink registry: `logtree_sink(fn)` registers any function of one argument and
  returns an id, `logtree_sinks()` lists ids in firing order, and
  `logtree_sink_remove(id)` unregisters, handing back the removed functions so the
  removal can be undone. `logtree_sink_file()` now returns an id too; the console
  sink lives under the reserved id `"console"`. A sink that throws is skipped with
  a single warning rather than breaking the fanout. `logtree_reset()` still leaves
  sinks alone -- they are configuration, and removal is the explicit path.

* New memory sink for asserting on your own logging:
  `logtree_sink_memory(max = 1000)` buffers events and
  `logtree_sink_memory_events(id)` reads them back as a data frame, one row per
  event -- so a test can ask *did this pipeline log what it should* without
  pattern-matching console glyphs. Its columns are a `"json"` sink's columns,
  enforced by a shared `event_record()`, so a replayed log file and the same run
  read from memory cannot disagree.

* Per-sink verbosity: `logtree_sink_file()`, `logtree_sink()` and
  `logtree_sink_memory()` take `threshold = `, so a log file can capture
  everything without dragging the console down with it. The global
  `logtree_threshold()` is the default for sinks that do not pin one, read afresh
  per event. Step open/close lines are never gated.

* New `logtree_mute()` / `logtree_unmute()` and a `logtree.silent` option read at
  load: gates the fanout while leaving the registry untouched, so a library can
  silence its own test suite without discarding its sink configuration. Both
  return the state they replaced. A muted run is still *recorded* (the flag is
  checked after the digest sees the event), so `logtree_summary()` still prints
  when called; only the unasked-for `with_logging()` run-summary line is
  suppressed. Depth bookkeeping is untouched, and the flag survives
  `logtree_reset()`.

## Theme

* New `trace` slot: an opt-in call-site column saying *where in your code* a line
  came from. `list(trace = list(show = "problems"))` annotates warning/error
  leaves and interrupted steps; `show = TRUE` covers every line that can carry
  one; `show` also takes statuses directly (`"error"`, `c("error",
  "interrupted")`, `"running"`). An ordinary close line never carries one -- its
  site is its own open line's. The same filter governs the `logtree_summary()`
  digest, and `logtree_summary(trace = )` pins it for a single call the way `gap`
  and `rule` do; it can only narrow what was captured, which is what
  `capture = TRUE` is for (record everywhere, print nothing -- a quiet tree with
  an annotated digest or `"json"` sink). Content is a template over `{fn}`,
  `{file}`, `{line}` (default `"{file}:{line} {fn}()"`), styled by
  `color = list(base=, location=, fn=)`; the location is printed relative to the
  working directory and emitted as a terminal hyperlink. It is appended to the
  message, so it wraps with it and never shears the tree. `logtree_sink_file()`
  gains a `trace` argument. `{file}`/`{line}` need `keep.source` (absent under
  plain `Rscript`); runs whose placeholders are all missing are dropped rather
  than rendered as `NA`. `show` is `FALSE` in all five presets, and with it off
  nothing is captured. Two call sites were fixed to make this honest: an error
  caught by `with_logging()` now traces to the condition's own call rather than to
  the calling handler, and a `logger` line now uses the `.topcall` it passes in
  rather than tracing to `layout_logtree()`.

* New `timestamp` slot: an opt-in wall-clock column in front of every line.
  `list(timestamp = list(format = "%H:%M:%S"))` switches it on; `NULL` (all five
  presets) is off. Width is measured from a rendered sample, not the format
  string, since `"%B"` is five columns in March and eight in December. It counts
  against the wrapping budget, and a wrapped message's continuation rows carry a
  blank column -- one event happened once. The `with_logging()` run-summary line
  is stamped; the `logtree_summary()` digest is not, since it replays events that
  already happened. `logtree_sink_file()` gains a `timestamp` argument.

* New `elapsed` slot for the time column on close lines: `show = FALSE` drops it,
  `min` hides anything faster than a threshold (silencing `0.00s` noise), `color`
  styles it, and `slow` + `slow_color` restyle the ones worth noticing. The
  run-summary line takes the colouring but never the hiding rules. Defaults leave
  output unchanged.

* New `done` slot: a step's own close line is styled separately from
  `log_success()` leaves, which keep `success`. Every preset ships the same glyph
  in both, so default output is unchanged.

* The word a step prints when it closes is themeable via a `text` field on a
  status slot, read from the closing status's slot and falling back to `done`'s
  then `"Done"` -- so `list(done = list(text = "Complete"))` renames every close
  line and `list(error = list(text = "Failed"))` only the failures. `text = ""`
  drops the word; `{label}` and `{elapsed}` are expanded, and a template placing
  `{elapsed}` itself owns that column.

* New `crumb` slot (`glyph`, `color`, `path_color`) for `logtree_summary()`
  breadcrumbs: path nodes carry an emphasis and the separator its own dimmer
  style, while a leaf's message stays unstyled. An angle quote in the unicode and
  emoji presets, plain `>` in ascii.

* New `summary` slot (`gap`, `rule`, `line`): `logtree_summary()` now sets its
  digest off from the tree with a blank gap and a `cli` rule labelled with the
  counts, so it reads as its own block. `gap` and `rule` override the layout for a
  single call (`rule = FALSE` restores the old plain header, a string titles the
  rule).

* Two new horizontal knobs on `logtree_theme()`: `glyph_gap` (spaces between a
  line's status glyph and its message, applied to every line kind so the message
  column stays aligned) and `connector_gap` (spaces between a *leaf or close*
  line's connector and its glyph). `connector_gap` tracks `col_gap` unless set, so
  `compact = "tight"` can keep rail columns flush while leaf glyphs still get air
  (`|- i msg` rather than `|-i msg`); it never touches a step's open line or a
  group header, and does not compound with depth. Both default to existing
  behaviour.

* New `"ci"` preset: bracketed word glyphs (`[step]`, `[info]`, `[debug]`, `[ok]`,
  `[done]`, `[warn]`, `[fail]`, `[break]`) over pure-ASCII connectors with no
  colour, so a captured build log survives a runner that strips ANSI and mangles
  UTF-8 and a failure greps as `[fail]`. Each word declares its true width, so the
  message column still lines up; unlike `ascii`, the corner (`\-`) differs from the
  branch (`|-`).

* New `"minimal"` preset: no tree connectors at all -- depth is carried by
  indentation alone (two columns per level), so output stays legible where
  box-drawing characters do not survive. Also a lighter glyph vocabulary, dimmed
  elapsed times, no group marker and wordless close lines. The trade: `info`,
  `debug` and `interrupted` all render the middle dot and are told apart by colour.

## Other

* Console output now wraps by default: long messages are word-wrapped at
  `cli::console_width()` instead of running off the right edge.
  `logtree_theme(wrap = )` governs it -- `TRUE` follows the terminal (measured at
  render time, so a mid-run resize is picked up), a number pins a width, `FALSE`
  restores the old behaviour. Continuation lines indent to the message column and
  carry the rails down, so a wrapped message still reads as one node. An unbreakable
  token is split by display width, and a budget narrower than the tree is deep
  degrades to no wrapping. It covers the digest and run-summary lines too; file
  sinks are never wrapped.

* `with_logging(warnings = TRUE)` routes R's own conditions into the tree:
  `warning()` becomes a `log_warn()` leaf and `message()` a `log_info()` leaf, at
  the depth where they happened. `warnings = "warning"` routes only the one kind.
  Off by default, deliberately: routing means **muffling** -- a routed condition
  no longer reaches `warnings()`, the caller's handlers or stderr. A routed
  warning also elevates its enclosing step, so wrapping noisy third-party code
  will turn steps yellow. In global mode the routing applies only while logtree
  steps are open.

* The `logger` integration declares the version it needs:
  `Suggests: logger (>= 0.3.0)`. `logtree_logger()` uses `logger::appender_void`,
  which arrived in 0.3.0; guards previously checked only whether `logger` was
  installed, so an older one failed with `'appender_void' is not an exported
  object` in examples, the vignette and tests instead of being skipped. Guards
  check the version now, and `logtree_logger()` refuses an old `logger` up front.

## Bug fixes

* `logtree_theme()` swaps a preset only when one is named. A call passing just
  `overrides` or `compact` used to re-resolve the `theme` default and silently
  reset everything to `"unicode"`. Such a call now merges onto the active theme,
  as documented; a bare `logtree_theme()` is a no-op.

* An unknown slot in a `logtree_theme()` override is now an error naming the slot
  and listing the valid ones, instead of failing inside `modifyList()` with
  `is.list(x) is not TRUE`.

# logtree 0.1.0

* Initial CRAN submission.
