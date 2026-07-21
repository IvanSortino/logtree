local_reset_verbosity <- function(envir = parent.frame()) {
  withr::defer(logtree_threshold("info"), envir = envir)
}
