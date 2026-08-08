# Deterministic call-site locations for tests that render a real tree.
#
# A trace's file:line is where the log call sits in *this* file, so a snapshot or
# a literal expectation over real output would break every time a line is added
# above the test. src_parts() is a package-internal free function called by name,
# so it mocks exactly the way helper-clock.R's freeze_clock() mocks now().
#
# Only the location is frozen -- `fn` still comes from the real frame stack,
# which is the half worth asserting on.
freeze_srcref <- function(file = "demo.R", line = 1L, path = NA_character_,
                          envir = parent.frame()) {
  testthat::local_mocked_bindings(
    src_parts = function(call) {
      list(file = file, line = as.integer(line), path = path)
    },
    .package = "logtree",
    .env = envir
  )
}

# Scope a trace setting to the current test, restoring the active preset after.
# Pairs with local_ascii_theme(), which must be called first if you want both.
local_trace <- function(show = TRUE, ..., envir = parent.frame()) {
  logtree_theme(list(trace = utils::modifyList(list(show = show), list(...))))
  withr::defer(logtree_theme(list(trace = list(show = FALSE))), envir = envir)
}

# A hand-built trace, for formatter tests that bypass capture entirely.
test_trace <- function(fn = "load_data", file = "pipeline.R", line = 12L,
                       path = NA_character_) {
  list(fn = fn, file = file, line = as.integer(line), path = path)
}
