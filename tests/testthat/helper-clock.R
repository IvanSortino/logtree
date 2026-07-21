freeze_clock <- function(times, envir = parent.frame()) {
  i <- 0
  testthat::local_mocked_bindings(
    now = function() {
      i <<- i + 1
      times[[min(i, length(times))]]
    },
    .package = "logtree",
    .env = envir
  )
}
