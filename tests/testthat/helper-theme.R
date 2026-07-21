local_ascii_theme <- function(envir = parent.frame()) {
  logtree_theme("ascii")
  withr::defer(logtree_theme("unicode"), envir = envir)
}
