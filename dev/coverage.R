#!/usr/bin/env Rscript
# Local test-coverage report for logtree. Run from the package root:
#   Rscript dev/coverage.R
#
# Prints overall + per-file coverage, lists any remaining uncovered lines, and
# writes a browsable HTML report to dev/coverage-report.html. Purely local: no
# Codecov upload, no token, no CI step. `dev/` is .Rbuildignore'd, so none of
# this ships in the built package.

if (!requireNamespace("covr", quietly = TRUE)) {
  stop("Install 'covr' first: install.packages('covr')", call. = FALSE)
}

cov <- covr::package_coverage()

cat("\n== Coverage ==\n")
print(cov)

cat("\n== Uncovered lines ==\n")
z <- covr::zero_coverage(cov)
if (nrow(z) == 0L) {
  cat("none - full line coverage\n")
} else {
  print(z[, intersect(c("filename", "line", "functions"), names(z))])
}

report <- file.path("dev", "coverage-report.html")
ok <- tryCatch({
  covr::report(cov, file = report, browse = FALSE)
  TRUE
}, error = function(e) {
  cat("\nHTML report skipped:", conditionMessage(e), "\n")
  FALSE
})
if (ok) cat("\nHTML report: ", report, "\n", sep = "")
