# logtree 0.1.1

* New `done` theme slot: a step's own `Done` line (a clean close) is styled
  separately from `log_success()` leaf lines, which keep the `success` slot.
  Every preset ships the same glyph in both, so default output is unchanged;
  `logtree_theme(overrides = list(done = list(glyph = "=")))` now restyles only
  the close lines, and a `success` override only the leaves.

# logtree 0.1.0

* Initial CRAN submission.
