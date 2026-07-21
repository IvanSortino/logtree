# log_debug() -- the most verbose leaf level, hidden by default
# (verbosity = "info") and shown once verbosity is raised to "debug". A
# suppressed debug leaf never elevates the enclosing step's status (like
# log_info()/log_success(), unlike log_warn()/log_error()).
#
#   source("debug/10_debug_level.R")
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")

fetch <- function() {
  log_step("Fetch")
  log_debug("cache miss for key user:42")
  log_info("requesting from API")
  log_debug("request took 84ms")
  log_success("fetched 12 records")
}

# --- A. default verbosity ("info") -- debug lines are hidden ---------------
section("A. default verbosity (info) -- debug hidden")
logtree_reset()
logtree_threshold("info")
with_logging(fetch(), summary = FALSE)

# --- B. verbosity = "debug" -- shown, under every theme --------------------
for (th in c("unicode", "ascii", "emoji")) {
  section(paste0("B. verbosity = debug, theme = ", th))
  logtree_reset()
  logtree_set_theme(th)
  logtree_threshold("debug")
  with_logging(fetch(), summary = FALSE)
}

logtree_set_theme("unicode")
logtree_threshold("info")
