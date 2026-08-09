# logtree (development version)

* The `logger` integration now declares the version it actually needs:
  `Suggests: logger (>= 0.3.0)`. `logtree_logger()` pairs logtree's layout with
  `logger::appender_void`, which arrived in `logger` 0.3.0, so against an older
  one it failed with `'appender_void' is not an exported object` -- and since
  every guard asked only whether `logger` was *installed*, that failure surfaced
  in examples, the vignette and the tests rather than being skipped. The guards
  check the version now, and `logtree_logger()` refuses an old `logger` up front
  with a message naming the requirement.

* New sink registry. `the$sinks` used to be an append-only list with no way to
  add a sink of your own and no way to take any of them off again; a test that
  registered one leaked it into every later test in the same session.
  `logtree_sink(fn)` registers any function of one argument and returns its id,
  `logtree_sinks()` lists the ids in the order they fire, and
  `logtree_sink_remove(id)` unregisters -- handing back the functions it removed,
  so the removal can be undone. `logtree_sink_file()` returns an id too, where it
  previously returned an invisible `NULL`, so a log file can be closed the same
  way. The console sink sits under the reserved id `"console"` and can be
  targeted like any other. `logtree_reset()` still leaves sinks alone: they are
  configuration rather than run state, and removal is now the explicit path.
  A sink that throws no longer breaks the fanout mid-flight -- it is skipped, the
  remaining sinks still run, and a warning naming it is raised once.

* New memory sink, for asserting on your own logging rather than eyeballing it.
  `logtree_sink_memory(max = 1000)` collects events in a capped buffer and
  `logtree_sink_memory_events(id)` reads them back as a data frame, one row per
  event, so a test can ask *did this pipeline log what it should* without
  capturing console output and pattern-matching glyphs and connectors it does not
  care about. Its columns are the ones a `"json"` sink writes, and that is now
  enforced rather than hoped for: both are built from one shared `event_record()`,
  so a run replayed from a log file and the same run read from memory cannot
  disagree.

* Sinks can set their own verbosity. `logtree_threshold()` was global, so turning
  it down to `"debug"` so a log file captured everything dragged the console down
  with it. `logtree_sink_file()`, `logtree_sink()` and `logtree_sink_memory()`
  now take `threshold = `, and the global level is simply the default for sinks
  that do not pin one -- read afresh per event, so moving it still moves them.
  Step open/close lines are never gated, whatever the threshold.

  **Behaviour change**: verbosity is now a *rendering* gate only. A warning
  suppressed by `logtree_threshold("error")` already elevated its step's close
  glyph; it now also reaches the `logtree_summary()` digest, rather than being
  forgotten because the console happened to be quiet. `summary = TRUE`/`FALSE`
  still pin and exclude a line as before.

* **Breaking change to the NDJSON schema**: a `"json"` sink's `ts` is now
  ISO-8601 to the millisecond with a UTC offset
  (`"2026-01-02T03:04:05.000+0000"`) rather than a bare epoch number no
  aggregator could interpret, and each record carries a `run_id` so one run's
  lines can be picked out of a file that many runs appended to. The id is derived
  from the wall clock and the process id rather than sampled, so a logger cannot
  perturb the RNG stream of a script that has just called `set.seed()`; it is
  refreshed per `with_logging()` call and per `logtree_reset()`.

* New `timestamp` theme slot: an opt-in wall-clock column in front of every line.
  A live tree said how *long* each step took but never *when* any of it happened,
  so a log read afterwards could not be lined up against anything else.
  `logtree_theme(list(timestamp = list(format = "%H:%M:%S")))` switches it on;
  `format` is a `strftime` template and `NULL` -- what all five presets ship --
  is off, so default output is unchanged and the feature costs a single list
  lookup per line until asked for.

  The column is padded to a fixed width measured from a rendered sample rather
  than from the format string, because a template is not its own width: `"%-d %b"`
  is five columns one day and six the next, and trusting it would shear the tree
  from one line to the next. It counts against the wrapping budget like any other
  column, and a wrapped message's continuation rows carry a *blank* column rather
  than a repeated time -- one event happened once. The `with_logging()`
  run-summary line is stamped, being printed as the run ends; the
  `logtree_summary()` digest is not, because it replays events that already
  happened. `logtree_sink_file()` gains a matching `timestamp = ` argument so a
  file can stamp its lines while the console stays bare, or the reverse.

* `with_logging(warnings = TRUE)` routes R's own conditions into the tree: a
  `warning()` raised by wrapped code becomes a `log_warn()` leaf and a `message()`
  becomes a `log_info()` leaf, at the depth where they happened. Previously they
  went to stderr, outside the tree, while a `log_warn()` call rendered inside it
  -- the same severity in two different places. `warnings = "warning"` routes only
  the one kind, for code that uses `message()` for progress chatter.

  It is off by default, and deliberately: routing means **muffling**. A routed
  condition stops at the leaf and no longer reaches `warnings()`, the caller's own
  handlers, or stderr. That is the right trade when the tree is meant to be the
  single record of a run, and the wrong one to make for somebody without asking.
  A routed warning also elevates its enclosing step, exactly as `log_warn()` does,
  so wrapping noisy third-party code will turn steps yellow. In global mode the
  routing applies only while logtree steps are open, so a session-persistent
  handler cannot swallow warnings from unrelated code.

* New `logtree_mute()` / `logtree_unmute()`, plus a `logtree.silent` option read
  at load. A library that logs with logtree had no way to keep its own test suite
  quiet short of unregistering the console sink, which throws away the
  configuration to get silence. Muting gates the fanout instead: every sink stops
  receiving events while the registry is left exactly as it was. Both functions
  return the state they replaced, so a function that mutes can restore what it
  found. A muted run is still *recorded* -- the flag is checked after the digest
  has seen the event -- so it can still be asked what went wrong at the end, and
  `logtree_summary()` still prints when called, while `with_logging()`'s
  run-summary line, which nobody asked for, is silenced. Step bookkeeping is
  untouched, so depth is right the moment output comes back, and like registered
  sinks the flag survives `logtree_reset()`.

* New `trace` theme slot: an opt-in call-site column, so a line can say *where
  in your code* it came from as well as what happened. `logtree_theme(list(trace
  = list(show = "problems")))` annotates only warning and error leaves plus
  steps that were interrupted -- the lines you go looking for a source location
  on -- and `show = TRUE` extends that to every line that can carry one. When
  that bundle is more than you want, `show` also takes the statuses themselves:
  `"error"` annotates errors and leaves tolerated warnings bare, `c("error",
  "interrupted")` adds the steps that never finished, `"running"` names open
  lines. An ordinary close line never carries a call site whatever you name --
  its site is its own open line's. The same filter applies to
  `logtree_summary()`'s digest, so a status named once means the same thing
  everywhere (a line pinned into the digest with `summary = TRUE` therefore
  carries a call site only when its own status is in the set), and
  `logtree_summary(trace = )` pins the digest's column for a single call the way
  `gap` and `rule` already pin its layout -- for when the tree was quiet and the
  digest is where you want the locations, or the reverse. It can only narrow or
  reshape what was captured, since capture is decided while the run happens --
  which is what the slot's `capture` field is for: `list(trace = list(show =
  FALSE, capture = TRUE))` records a call site on every line while printing
  none, so a tree that stays exactly as quiet as it was can still hand locations
  to the digest or a `"json"` sink. It only ever adds; a `show` that asks for a
  column already implies capture. The column's
  content is a template over `{fn}`, `{file}` and `{line}` (default
  `"{file}:{line} {fn}()"`), styled by the slot's `color` -- which takes a
  `list(base=, location=, fn=)` so the parts can be told apart, as the presets
  do: all of it dim, location in silver, function name in cyan. The location is
  printed relative to the working directory and is a single terminal hyperlink
  to that file and line, separator included, so a click anywhere on it opens
  your editor there where the terminal supports it. It is appended to the message rather than given a column
  of its own, so it wraps with the message and never shears the tree. Defaults leave output completely unchanged: `show` is `FALSE`
  in all five presets, and with it off nothing is captured at all, so the cost
  of the feature to a run that does not use it is a single list lookup per line.

  Two things worth knowing before switching it on. First, `{file}` and `{line}`
  depend on R's source references, which exist when code was parsed with
  `keep.source = TRUE` -- the default interactively and under
  `devtools::load_all()`, but not under plain `Rscript` or for an installed
  package. `{fn}` always works, and rather than print `NA` the expander drops
  any run of the template whose placeholders are all missing, so the default
  degrades to `load_data()`. Second, the trace also reaches
  `logtree_summary()`'s digest lines (where it is arguably most useful, that
  being the view you read after a failed run) and the `fn` / `file` / `line`
  fields of a `"json"` sink. `logtree_sink_file()` gains a `trace` argument so a
  file sink can record call sites while the console column stays off, or pin
  itself independently of whatever the console is doing.

  Two call sites needed fixing to make this honest rather than merely present.
  An error caught by `with_logging()` is logged from inside a calling handler, so
  a naive frame walk would report the handler as the origin of every uncaught
  error; it now uses the condition's own call, which makes this the most useful
  trace in the package -- it points at the line that actually threw. Likewise a
  `logger` line routed through `layout_logtree()` would have traced to
  `layout_logtree` itself; it now uses the `.topcall` that `logger` has always
  passed in and that logtree previously documented as unused.

* `logtree_theme()` gains `connector_gap`, the spaces between a *leaf or close*
  line's own connector and its status glyph -- the middle one of logtree's
  three horizontal knobs, between `compact` (the per-level rail column) and
  `glyph_gap` (glyph to message). Unset it tracks `col_gap`, so every preset
  and every `compact` density renders exactly as before; set it and the two
  diverge, which is the point: `compact = "tight"` can keep every rail column
  flush while leaf and close glyphs still get air (`|- i msg` rather than
  `|-i msg`). It deliberately never touches a step's *open* line or a group
  header -- those are rail columns, not the glyph's own approach, so they stay
  flush at any density -- and the gap does not compound with depth, so a deeper
  tree does not fan out to the right.

* Console output now wraps by default: a long message is word-wrapped at
  `cli::console_width()` instead of running off the right edge. The new
  `logtree_theme(wrap = )` governs it -- `TRUE` (the console default) follows
  the terminal, measured at render time so a mid-run resize is picked up on its
  own, a number pins a fixed width, and `FALSE` restores the old overflowing
  behaviour. Continuation lines indent to the message column and carry the
  rails down, so a wrapped message still reads as one node of the tree: after a
  branch connector the rail continues, after a corner it does not, and a
  step-open line or group header also rails its own glyph/marker column, which
  is where its children hang. A token with no break opportunity (a long path, a
  URL) is split by display width rather than left to overflow, and a budget
  narrower than the tree is deep degrades to no wrapping rather than to an
  unusable one-column line. It covers every line logtree renders, including the
  `logtree_summary()` digest and the `with_logging()` run-summary line. File
  sinks are never wrapped -- a file has no width to wrap to.

* New `"ci"` theme preset: `logtree_theme("ci")` renders bracketed word glyphs
  -- `[step]`, `[info]`, `[debug]`, `[ok]`, `[done]`, `[warn]`, `[fail]`,
  `[break]` -- over pure-ASCII connectors with no colour in any slot, so a
  captured build log survives a runner that strips ANSI and mangles UTF-8, and
  a failure greps as `[fail]` rather than as a glyph you cannot type into a
  search box. The words are different lengths on purpose: each declares its
  true width, so the message column still lines up. Unlike the `ascii` preset
  it spells the corner (`\-`) differently from the branch (`|-`), which makes a
  closed subtree obvious in a wall of output.

* New `"minimal"` theme preset: `logtree_theme("minimal")` draws no tree
  connectors at all -- `branch`, `corner` and `pipe` are empty, so depth is
  carried by indentation alone (two columns per level) and the output stays
  legible when pasted somewhere box-drawing characters do not survive. It also
  ships a lighter glyph vocabulary, dimmed elapsed times, no group marker, and
  wordless close lines, so a closing step is a tick and a time. The trade is
  deliberate and worth knowing: `info`, `debug` and `interrupted` all render
  the middle dot and are told apart by colour alone.

* New `elapsed` theme slot controls the time column on close lines, with five
  fields: `show = FALSE` drops it entirely, `min` hides anything faster than a
  threshold (`logtree_theme(list(elapsed = list(min = 0.1)))` silences the
  `0.00s` noise on trivial steps), `color` styles the time, and `slow` +
  `slow_color` restyle the ones worth noticing -- so a step that ran long is
  visible at a glance without reading every number. It is an ordinary override
  slot, so it needs no new `logtree_theme()` argument. The `with_logging()`
  run-summary line takes the colouring but never the hiding rules, since
  `Run complete in <time>` would read as an unfinished sentence without its
  time. The defaults (`show = TRUE`, `min = 0`, no `slow`) leave output
  unchanged.

* The word a step prints when it closes is themeable: the new `text` field on a
  status slot replaces the hard-coded `Done`. It is read from the closing
  status's own slot, falling back to `done`'s and then to `"Done"`, so
  `logtree_theme(list(done = list(text = "Complete")))` renames every close
  line while `list(error = list(text = "Failed"))` renames only the ones that
  went wrong -- which is also all localisation needs. `text = ""` drops the
  word, leaving the glyph and the elapsed time. Two placeholders are expanded:
  `{label}` (the step's own label, or a group's name) and `{elapsed}` (the
  formatted time); a template that places `{elapsed}` itself owns that column
  rather than having the time appended twice. `text` governs close lines only
  -- `log_error()`'s own message is untouched -- and every preset ships
  `text = "Done"`, so existing output is unchanged.

* `logtree_theme()` gains `glyph_gap`, the number of spaces between a line's
  status glyph and its message: `0` butts the message against the glyph for a
  minimal look, `2` or more airs the message column out. It applies to every
  line kind (step open, `Done` close, leaf, group header, and the
  `with_logging()` run-summary line) so the message column stays aligned, and
  composes with `compact`, which tunes the other horizontal column. Like
  `compact`, it rides the active console theme and is cleared by a preset swap;
  file sinks keep their built-in spacing. The default of one space leaves
  existing output byte-for-byte unchanged.

# logtree 0.2.0

* New `done` theme slot: a step's own `Done` line (a clean close) is styled
  separately from `log_success()` leaf lines, which keep the `success` slot.
  Every preset ships the same glyph in both, so default output is unchanged;
  `logtree_theme(overrides = list(done = list(glyph = "=")))` now restyles only
  the close lines, and a `success` override only the leaves.

* `logtree_summary()` sets its digest off from the log tree: a blank gap and a
  `cli` rule labelled with the digest's counts, so the summary reads as its own
  block instead of one more branch. `gap` and `rule` override the layout for a
  single call (`rule = FALSE` restores the old plain header line, a string
  titles the rule); the defaults live in the new `summary` theme slot (`gap`,
  `rule`, `line`).

* `logtree_summary()` breadcrumbs are easier to scan: the path nodes carry an
  emphasis and the separator its own dimmer style, while a leaf's message stays
  unstyled, so context and content are told apart at a glance. The separator is
  the new `crumb` theme slot (`glyph`, `color`, `path_color`) -- an angle quote
  in the unicode and emoji presets, plain `>` in ascii.

* `logtree_theme()` swaps a preset only when one is named. Previously a call
  passing just `overrides` or `compact` re-resolved the `theme` default and
  silently reset the whole theme to `"unicode"` -- overriding one glyph while on
  the ascii preset put back the unicode glyph set. Such a call now merges onto
  the active theme, as documented. A bare `logtree_theme()` is a no-op; reset
  with `logtree_theme("unicode")`.

* An unknown slot in a `logtree_theme()` override is now an error naming the
  slot and listing the valid ones, instead of failing inside `modifyList()`
  with `is.list(x) is not TRUE`.

# logtree 0.1.0

* Initial CRAN submission.
