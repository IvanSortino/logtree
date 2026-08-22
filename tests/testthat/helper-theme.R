# Wrapping is on by default on the console, which would make every rendered
# line depend on the width of whatever terminal the suite happens to run in.
# Tests that assert on output pin it off; test-wrap.R sets its own widths.
local_ascii_theme <- function(envir = parent.frame()) {
  logtree_theme("ascii", wrap = FALSE)
  withr::defer(logtree_theme("unicode"), envir = envir)
}
