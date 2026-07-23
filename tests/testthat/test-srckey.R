# Content-key reconcile: re-running a top-level line re-anchors to the same
# node instead of nesting. Auto-keying only engages when the caller frame is
# globalenv(), which is never true inside a test_that() block, so these tests
# drive the same reconcile via the explicit `key=` path (and push_step() with
# synthetic srcrefs for the disambiguation logic).

depths <- function() vapply(the$stack, function(e) e$depth, integer(1))

test_that("re-running a keyed step re-anchors instead of nesting", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  id1 <- log_open("Load", key = "Load")
  log_open("Parse", key = "Parse")
  expect_equal(depths(), c(1L, 2L))

  # Re-run the "Load" line while the previous run is still open: it should
  # rewind (close Parse) and reuse the Load node, not descend.
  id2 <- log_open("Load", key = "Load")
  expect_length(the$stack, 1L)
  expect_equal(the$stack[[1]]$label, "Load")
  expect_equal(depths(), 1L)
  # Reuse keeps the original step id stable.
  expect_identical(id1, id2)

  # Re-running the rest of the block rebuilds the same tree, no deeper.
  log_open("Parse", key = "Parse")
  expect_equal(depths(), c(1L, 2L))
})

test_that("explicit distinct keys keep same-label steps distinct", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  log_open("Same", key = "a")
  log_open("Same", key = "b")
  expect_length(the$stack, 2L)
  expect_equal(depths(), c(1L, 2L))
})

test_that("no key: normal nesting is unchanged", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  # No key and not at top level -> auto-key does not engage -> plain nesting.
  log_open("A")
  log_open("B")
  expect_length(the$stack, 2L)
  expect_equal(depths(), c(1L, 2L))
})

test_that("srcref disambiguates colliding labels, then reuses on exact match", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  push_step("X", key = "X", srcref = "f:1")
  push_step("X", key = "X", srcref = "f:2") # same label, different call site -> nest
  expect_equal(depths(), c(1L, 2L))

  # A push from the outer call site (f:1) matches by srcref -> reuse, rewind f:2.
  push_step("X", key = "X", srcref = "f:1")
  expect_length(the$stack, 1L)
  expect_equal(the$stack[[1]]$srcref, "f:1")
})

test_that("without srcref, reconcile reuses the outermost label match", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  push_step("A", key = "A", srcref = NA_character_)
  push_step("B", key = "B", srcref = NA_character_)
  push_step("A", key = "A", srcref = NA_character_) # reuse A, rewind B
  expect_length(the$stack, 1L)
  expect_equal(the$stack[[1]]$label, "A")
})

test_that("reconcile_open_step returns NULL when key is NULL or unmatched", {
  logtree_reset()
  withr::defer(logtree_reset())

  expect_null(reconcile_open_step(NULL, NULL))
  push_step("A", key = "A", srcref = NA_character_)
  expect_null(reconcile_open_step("B", NA_character_))
  expect_equal(reconcile_open_step("A", NA_character_), 1L)
})

test_that("src_location returns NA without a source ref, file:line with one", {
  # quote() carries no srcref -> NA disables srcref disambiguation.
  expect_true(is.na(src_location(quote(foo()))))

  # R attaches a call's srcref during evaluation (sys.call() carries it); a
  # statically parsed element does not, so attach it as R would at eval time.
  exprs <- parse(text = 'log_open("z")', keep.source = TRUE)
  call <- exprs[[1]]
  attr(call, "srcref") <- attr(exprs, "srcref")[[1]]
  loc <- src_location(call)
  expect_match(loc, ":1$")
})

test_that("re-anchoring emits a close line for the rewound deeper step", {
  logtree_reset()
  withr::defer(logtree_reset())
  local_ascii_theme()

  log_open("A", key = "A")
  out <- capture.output({
    log_open("B", key = "B")
    log_open("A", key = "A") # rewinds B -> B closes
  })
  expect_true(any(grepl("Done", out)))
})
