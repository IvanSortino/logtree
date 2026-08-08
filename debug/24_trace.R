# Call-site trace: the `trace` theme slot annotates log lines with where in
# your code they came from.
#
#   show   -- FALSE (default) off entirely; TRUE on every line that can carry a
#             call site; "problems" shorthand for warnings, errors and
#             interrupted steps; or a vector of the statuses themselves --
#             "running" (open lines), "info"/"debug"/"success"/"warning"/
#             "error" (leaves) and "interrupted" (a step that unwound)
#   format -- a template over {fn}, {file} and {line}, default
#             "{file}:{line} {fn}()"
#   color  -- cli styles: one vector for the whole column, or a named list
#             styling location / fn / base separately (what the presets ship)
#
# The location -- {file}, the ":" and {line} together -- is also a single
# terminal hyperlink to that file at that line, so a click anywhere on it opens
# the file. That needs a resolvable path, which is why {file} prints
# relative to the working directory rather than as a bare basename -- run this
# from the repo root and the locations below read "debug/24_trace.R:NN".
#
# It is an ordinary override slot, so it goes through logtree_theme()'s
# `overrides` like any glyph slot -- no new argument.
#
# The one thing worth understanding before reading the output: {file} and {line}
# come from source references, which exist only when code was parsed with
# keep.source = TRUE. That is the default interactively and under
# devtools::load_all(), but NOT under plain `Rscript`. {fn} always works. So the
# default format degrades from "load_data() pipeline.R:12" to "load_data()"
# rather than printing NA -- section G shows that on purpose.
#
#   Rscript -e 'devtools::load_all(); source("debug/24_trace.R")'
devtools::load_all()

section <- function(title) cat("\n\033[1m== ", title, " ==\033[0m\n")
run_section <- function(title, ...) {
  section(title)
  logtree_reset()
  logtree_theme("unicode", ...)
  on.exit(logtree_theme("unicode"), add = TRUE)
  with_logging(tree(), summary = FALSE)
}

# One shared fixture, nested three deep, with a warning and an error at
# different levels so the "problems" mode has something to single out.
tree <- function() {
  log_step("Pipeline")
  log_info("config loaded")
  load_data()
  summarise()
}
load_data <- function() {
  log_step("Load data")
  log_info("reading records.csv")
  parse_rows()
}
parse_rows <- function() {
  log_step("Parse rows")
  log_info("1200 rows")
  log_warn("coerced 3 rows")
}
summarise <- function() {
  log_step("Summarise")
  log_error("no numeric columns")
}

run_section("A. default -- trace off, output unchanged")

run_section("B. show = \"problems\" -- only where something went wrong",
            overrides = list(trace = list(show = "problems")))

# "problems" is a bundle. Naming statuses instead is how you take the errors and
# leave the tolerated warnings alone -- compare the "coerced 3 rows" line here
# with section B, where it carries a call site.
run_section("B2. show = \"error\" -- errors, without their warnings",
            overrides = list(trace = list(show = "error")))

# Statuses are the theme's own vocabulary, so anything that has a glyph slot can
# be named: here the errors plus any step whose frame unwound.
run_section("B3. show = c(\"error\", \"interrupted\") -- and the steps that died",
            overrides = list(trace = list(show = c("error", "interrupted"))))

# "running" is what an open line reports, so it is the token that turns *only*
# the open lines on -- the leaves below them stay bare.
run_section("B4. show = \"running\" -- open lines only",
            overrides = list(trace = list(show = "running")))

run_section("C. show = TRUE -- every line that can carry a call site",
            overrides = list(trace = list(show = TRUE)))

run_section("D. format = \"{fn}()\" -- the half that never degrades",
            overrides = list(trace = list(show = TRUE, format = "{fn}()")))

run_section("E. format = \"{file}:{line}\" -- location only",
            overrides = list(trace = list(show = TRUE,
                                          format = "{file}:{line}")))

# The parts are styled independently, so `color` takes a named list. Any subset
# is merged onto the preset's -- here only `fn` moves, and the location keeps
# its dim silver.
run_section("E2. color = list(fn = ...) -- one part restyled, rest inherited",
            overrides = list(trace = list(show = TRUE,
                                          color = list(fn = c("bold", "magenta")))))

# The pre-list form still works and still means "the whole column".
run_section("E3. color = \"blue\" -- one style over the whole column",
            overrides = list(trace = list(show = TRUE, color = "blue")))

# --- F. the digest -----------------------------------------------------------
# The digest is arguably where a trace earns its keep: it is what you read after
# a run failed, and it is the one view that already answers "what went wrong"
# without answering "where".
section("F. the summary digest carries call sites too")
logtree_reset()
logtree_theme("unicode", overrides = list(trace = list(show = "problems")))
with_logging(tree(), summary = FALSE)
logtree_summary()
logtree_theme("unicode")

# The digest applies the same filter, so a status named once means the same
# thing everywhere: only the error line below carries a location.
section("F2. the digest filters by status too (show = \"error\")")
logtree_reset()
logtree_theme("unicode", overrides = list(trace = list(show = "error")))
with_logging(tree(), summary = FALSE)
logtree_summary()
logtree_theme("unicode")

# --- G. degradation ----------------------------------------------------------
# Evaluate the same logging with keep.source = FALSE, so no srcrefs exist. The
# {file}:{line} run drops out of the template whole rather than rendering "NA".
section("G. no source refs (keep.source = FALSE) -- {fn}() survives alone")
logtree_reset()
logtree_theme("unicode", overrides = list(trace = list(show = TRUE)))
block <- parse(
  text = paste(
    'noloc <- function() { log_step("No srcrefs here"); log_info("still traced") }',
    'noloc()',
    sep = "\n"
  ),
  keep.source = FALSE
)
eval(block, envir = globalenv())
logtree_reset()
logtree_theme("unicode")

# --- H. file sinks -----------------------------------------------------------
# A text sink follows the console by default; pass `trace =` to pin it. Both
# paths target tempfile() -- writing to the working directory is a CRAN no.
section("H. file sinks: text follows the console, json always carries the fields")
logtree_reset()
logtree_theme("unicode", overrides = list(trace = list(show = "problems")))

txt  <- tempfile(fileext = ".log")
json <- tempfile(fileext = ".ndjson")
logtree_sink_file(txt,  format = "text")
logtree_sink_file(json, format = "json")
with_logging(tree(), summary = FALSE)

cat("\n-- text sink --\n")
cat(readLines(txt), sep = "\n")
cat("\n\n-- json sink (last two events) --\n")
cat(utils::tail(readLines(json), 2), sep = "\n")
cat("\n")

# A quiet console with a log file that still records call sites: the sink's own
# `trace =` switches capture on by itself.
#
# Sinks are additive and deliberately NOT cleared by logtree_reset(), and there
# is as yet no logtree_sink_remove() (debug/feature-plan.md item 4). A demo with
# more than one sink section therefore has to reach into internals to unregister
# the previous one -- the same `logtree:::the` poking 14_srckey_replay.R does.
# Note the local binding: `logtree:::the$x <- v` is a complex assignment, which R
# rewrites into a call needing `logtree` as an ordinary object, so it fails with
# "object 'logtree' not found". Bind the environment first, then assign through
# it -- environments are reference semantics, so it is the same state object.
# Do not copy this into real code.
drop_sinks <- function() {
  st <- logtree:::the
  st$sinks       <- list(logtree:::console_sink)
  st$trace_sinks <- 0L
}

section("I. trace = TRUE on the sink only -- console stays clean")
drop_sinks()
logtree_reset()
logtree_theme("unicode")
quiet <- tempfile(fileext = ".log")
logtree_sink_file(quiet, format = "text", trace = TRUE)
with_logging(tree(), summary = FALSE)
cat("\n-- the file, which has traces the console did not show --\n")
cat(readLines(quiet), sep = "\n")
cat("\n")

drop_sinks()
logtree_theme("unicode")

# --- J. the hyperlink --------------------------------------------------------
# The location is wrapped in an OSC 8 escape pointing at the absolute path, so a
# supporting terminal opens the file at that line when you click it. cli decides
# support from the terminal it finds itself in and prints plain text where there
# is none -- which is exactly what a piped `Rscript` run gets, hence the forced
# options and the escaped-bytes view below.
section("J. the location is a terminal hyperlink (escapes shown literally)")
tr <- list(fn = "load_data", file = "R/pipeline.R", line = 12L,
           path = file.path(getwd(), "R", "pipeline.R"))
withr::with_options(
  list(cli.num_colors = 256L, cli.hyperlink = TRUE),
  cat(encodeString(logtree:::render_trace_text(tr)), "\n")
)
logtree_reset()
