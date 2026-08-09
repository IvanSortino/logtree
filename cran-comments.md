## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Notes for the reviewer

* There are no published references describing the methods in this package,
  so the Description field contains no doi/arXiv/ISBN citation.
* All uses of suggested packages ('jsonlite', 'logger') are conditional:
  examples are guarded with `rlang::is_installed()`, tests with
  `testthat::skip_if_not_installed()`, and `logtree_logger()` calls
  `rlang::check_installed()` before touching the namespace.
* The 'logger' integration needs `appender_void`, added in 'logger' 0.3.0, so
  Suggests declares `logger (>= 0.3.0)` and every guard above checks that
  version rather than mere presence.
