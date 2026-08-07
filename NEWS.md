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
