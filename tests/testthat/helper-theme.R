local_ascii_theme <- function(envir = parent.frame()) {
  logtree_set_theme("ascii")
  withr::defer(logtree_set_theme("unicode"), envir = envir)
}
