# logtree 0.1.0

* Initial CRAN submission.
* `logtree_logger()` routes the `logger` package through logtree in a single call, registering the layout, no-op appender, and opening `logger`'s threshold so `logtree_threshold()` is the only gate.
