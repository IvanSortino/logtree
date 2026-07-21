test_that("adjacent steps sharing a group value collapse under one header", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  run <- function() {
    check <- function(item, label) log_step(label, group_by = c(g = item))
    log_step("Root")
    check(1, "a")
    check(1, "b")
  }
  out <- capture.output(run())

  # One header wraps both members; the group itself emits no "Done" line, so
  # the only close lines are the three real steps (Root, a, b).
  expect_equal(sum(grepl("< g >", out, fixed = TRUE)), 1L)
  expect_equal(sum(grepl("> a$", out)), 1L)
  expect_equal(sum(grepl("> b$", out)), 1L)
  expect_equal(sum(grepl("Done", out, fixed = TRUE)), 3L)
  expect_length(the$stack, 0)
})

test_that("a changed group value opens a new header", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  run <- function() {
    check <- function(item, label) log_step(label, group_by = c(g = item))
    log_step("Root")
    check(1, "a")
    check(2, "b")
  }
  out <- capture.output(run())

  expect_equal(sum(grepl("< g >", out, fixed = TRUE)), 2L)
  expect_length(the$stack, 0)
})

test_that("a plain step after a group is a sibling of the group, not a child", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  run <- function() {
    grouped <- function() log_step("g-step", group_by = c(g = 1))
    plain   <- function() log_step("plain")
    log_step("Root")
    grouped()
    plain()
  }
  out <- capture.output(run())

  # "g-step" sits one rail deeper than "plain": the lingering group is closed
  # before the plain step, so they render at different indents.
  expect_match(out[grep("> g-step$", out)], "^\\|  \\|- > g-step$")
  expect_match(out[grep("> plain$", out)], "^\\|- > plain$")
  expect_length(the$stack, 0)
})

test_that("grouped tree renders as expected (ascii snapshot)", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()
  freeze_clock(0)

  run <- function() {
    check <- function(item, label) {
      log_step(label, group_by = stats::setNames(item, paste0("Item ", item)))
      log_info(paste0(label, " running"))
    }
    process_item <- function(item) {
      check(item, "validate")
      check(item, "bounds")
    }
    log_step("Pipeline")
    for (i in 1:2) process_item(i)
    log_success("done")
  }
  expect_snapshot(cat(capture.output(with_logging(run(), summary = FALSE)), sep = "\n"))
})

test_that("json sink emits a group event with an id/parent_id chain", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()
  local_ascii_theme()

  path <- tempfile()
  logtree_sink_file(path, format = "json")

  run <- function() {
    check <- function(item, label) log_step(label, group_by = c(g = item))
    log_step("Root")
    check(1, "a")
    check(1, "b")
  }
  invisible(with_logging(run(), summary = FALSE))

  parsed <- lapply(readLines(path), function(l) jsonlite::fromJSON(l))
  for (p in parsed) {
    expect_true(all(c("id", "parent_id") %in% names(p)))
  }

  by_kind <- function(level) Filter(function(p) p$level == level, parsed)
  grp   <- by_kind("group")
  opens <- by_kind("open")

  # Exactly one group event, labelled by the vector name, statused "group".
  expect_length(grp, 1L)
  expect_equal(grp[[1]]$label, "g")
  expect_equal(grp[[1]]$status, "group")

  # Both member steps ("a", "b") point at the group's id as their parent.
  members <- Filter(function(p) p$label %in% c("a", "b"), opens)
  expect_true(all(vapply(members, function(p) p$parent_id, numeric(1)) == grp[[1]]$id))
  # The group's parent is the root step.
  root <- Filter(function(p) p$label == "Root", opens)[[1]]
  expect_equal(grp[[1]]$parent_id, root$id)
})

test_that("group_by requires a length-1 vector", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_reset_sinks()

  f <- function() log_step("x", group_by = c(a = 1, b = 2))
  expect_error(f(), "length-1")
})
