local_reset_sinks <- function(envir = parent.frame()) {
  withr::defer(the$sinks <- list(console_sink), envir = envir)
}
