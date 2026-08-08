.onLoad <- function(libname, pkgname) {
  the$theme     <- console_preset("unicode")
  the$verbosity <- "info"
  the$sinks     <- list(console_sink)
}
