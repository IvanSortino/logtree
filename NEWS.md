# logtree (development version)

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
