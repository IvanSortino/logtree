## R CMD check results

0 errors | 0 warnings | 0 notes

Two notes appear on the local macOS machine only and are properties of that
machine, not of the package:

* `checking for future file timestamps ... unable to verify current time` --
  the time-verification service was unreachable from this network.
* `checking HTML version of manual` -- macOS ships HTML Tidy 5.6 (2006), which
  does not recognise the HTML5 `<main>` element that R's own Rd-to-HTML
  converter emits. Every `.html` page in the manual reports it.

## Test environments

* local macOS 26.6.2 (aarch64), R 4.4.3 -- `R CMD check --as-cran`

## Submission notes

* This is a patch release of an existing package (logtree 0.2.0 is on CRAN).
  It fixes one bug: `with_logging(global = TRUE)` errored when condition
  handlers were on the stack (e.g. a script evaluated inside a runner's
  `tryCatch()`); it now warns and falls back to an exit-time finalizer. See
  NEWS.md.
* There are no reverse dependencies on CRAN, so nothing downstream is affected.
* There are no published references describing the methods in this package,
  so the Description field contains no doi/arXiv/ISBN citation.
* All uses of suggested packages ('jsonlite', 'logger') are conditional:
  examples are guarded with `rlang::is_installed()`, tests with
  `testthat::skip_if_not_installed()`, and `logtree_logger()` calls
  `rlang::check_installed()` before touching the namespace.
* The 'logger' integration needs `appender_void`, added in 'logger' 0.3.0, so
  Suggests declares `logger (>= 0.3.0)` and every guard above checks that
  version rather than mere presence.
