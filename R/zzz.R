.onLoad <- function(libname, pkgname) {
  the$theme     <- glyphs_unicode
  the$verbosity <- "info"
  the$sinks     <- list(console_sink)
}
