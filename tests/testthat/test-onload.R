test_that(".onLoad seeds the default theme, verbosity, and console sink", {
  # .onLoad runs at namespace load, before covr instrumentation attaches, so
  # exercise it directly. It mutates package-global state -> snapshot and
  # restore the three fields it touches.
  old_theme     <- the$theme
  old_verbosity <- the$verbosity
  old_sinks     <- the$sinks
  withr::defer({
    the$theme     <- old_theme
    the$verbosity <- old_verbosity
    the$sinks     <- old_sinks
  })

  the$theme     <- NULL
  the$verbosity <- NULL
  the$sinks     <- NULL

  .onLoad("lib", "logtree")

  expect_identical(the$theme, glyphs_unicode)
  expect_identical(the$verbosity, "info")
  expect_length(the$sinks, 1L)
  expect_identical(the$sinks[[1]], console_sink)
})
