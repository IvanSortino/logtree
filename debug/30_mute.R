# The mute switch: silence every sink at once, without unregistering any.
#
#   logtree_mute()            -- stop emitting; returns the previous state
#   logtree_unmute()          -- start again
#   options(logtree.silent = TRUE)   -- the initial state, read at load
#
# The case it exists for: a library that logs with logtree, whose own test
# suite should not print a tree for every fixture. Before this the only lever
# was to unregister the console sink, which loses the configuration and has to
# be put back by hand.
#
# Three things muting deliberately does not do, and each is worth seeing:
#
#   * it does not stop the run being *recorded* -- the digest still knows what
#     went wrong (section C)
#   * it does not disturb step bookkeeping -- depth is still right when output
#     comes back (section D)
#   * it does not survive being forgotten about: like sinks, and unlike the open
#     step stack, logtree_reset() leaves it alone (section E)
#
#   Rscript -e 'devtools::load_all(); source("debug/30_mute.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

pipeline <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  load_data()
}
load_data <- function() {
  log_step("Load data")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}

# --- A. the baseline ---------------------------------------------------------
section("A. unmuted -- the usual tree")
logtree_reset()
logtree_unmute()
with_logging(pipeline(), summary = TRUE)

# --- B. muted ----------------------------------------------------------------
# Nothing between the dashes: the tree, the leaves and with_logging()'s own
# "Run complete" line are all output nobody asked for, so all three go.
section("B. muted -- nothing at all, run summary included")
logtree_reset()
logtree_mute()
cat("-- start --\n")
with_logging(pipeline(), summary = TRUE)
cat("-- end --\n")

# --- C. still recorded -------------------------------------------------------
# The digest is a record rather than output, and printing it is something you
# asked for rather than something that happened to you. So it survives the mute
# in both senses: the run was recorded, and logtree_summary() still prints.
section("C. ... but the run was still recorded, and the digest still prints")
logtree_summary()

# --- D. bookkeeping is untouched ---------------------------------------------
# Muting is a gate on emit(), not on the stack. Steps still open and close while
# muted, so the line printed after unmuting sits at the depth it should --
# one connector under "Outer", not three.
section("D. depth is still correct when output comes back")
logtree_reset()
logtree_unmute()
outer <- function() {
  log_step("Outer")
  log_info("visible")
  logtree_mute()
  quiet_part <- function() {
    log_step("Quiet section")
    log_info("this line is never printed")
  }
  quiet_part()
  logtree_unmute()
  log_info("visible again, at the right depth")
}
invisible(outer())
cat("open steps left on the stack:", length(logtree:::the$stack), "\n")

# --- E. it outlives a reset --------------------------------------------------
section("E. logtree_reset() does not unmute -- like sinks, it is configuration")
logtree_mute()
logtree_reset()
cat("-- start --\n")
invisible(pipeline())
cat("-- end (still muted) --\n")
logtree_unmute()

# --- F. save and restore -----------------------------------------------------
# Both functions return the state they replaced, so a function that mutes can
# put back whatever it found rather than assuming its caller wanted noise.
section("F. mute/unmute return the previous state, so it can be restored")
quietly <- function(expr) {
  was <- logtree_mute()
  on.exit(if (!was) logtree_unmute(), add = TRUE)
  force(expr)
}
logtree_reset()
cat("caller was unmuted; quietly() runs a silent pipeline:\n")
cat("-- start --\n")
quietly(pipeline())
cat("-- end --\n")
cat("and afterwards output is back:\n")
logtree_reset()
invisible(pipeline())

# --- G. the option -----------------------------------------------------------
# options(logtree.silent = TRUE) seeds the flag when the package loads, for an
# .Rprofile or a test setup file. After load the functions are in charge, which
# is the same split logtree_threshold() has with its own default.
section("G. options(logtree.silent = TRUE) is read at load time only")
cat("setting the option now changes nothing on its own:\n")
withr::with_options(list(logtree.silent = TRUE), {
  logtree_reset()
  invisible(load_data())
})

logtree_unmute()
logtree_reset()
