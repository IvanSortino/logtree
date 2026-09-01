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
* win-builder, R-devel
* macOS builder (CRAN), R-release
* R-hub: linux (gcc), macos, windows

## Submission notes

* This is an update of an existing package (logtree 0.1.0 is on CRAN). It adds a
  sink registry, a memory sink, themeable call-site trace annotations, and
  changes the NDJSON event schema; see NEWS.md for the full list.
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
