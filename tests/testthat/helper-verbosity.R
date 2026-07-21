local_reset_verbosity <- function(envir = parent.frame()) {
  withr::defer(logtree_set_verbosity("info"), envir = envir)
}
