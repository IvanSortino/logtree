# The wall clock, frozen the same way freeze_clock() freezes the elapsed-time
# clock: `times` is recycled from its last element once exhausted, so a test can
# pin one instant for a whole run or step through several.
freeze_wall_clock <- function(times, envir = parent.frame()) {
  if (is.character(times)) times <- as.POSIXct(times, tz = "UTC")
  i <- 0
  testthat::local_mocked_bindings(
    wall_clock = function() {
      i <<- i + 1
      times[[min(i, length(times))]]
    },
    .package = "logtree",
    .env = envir
  )
}

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
