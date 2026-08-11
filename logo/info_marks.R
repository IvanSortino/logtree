# ================================================================
# logtree — the info marks and the branches that carry them
#
# Authored, not traced, which is why this is a file of its own rather
# than part of tree_paths.R: regenerating the trace must not clobber it.
# Sourced by both make_logo_traced.R and make_logo_numbered.R so the two
# cannot drift apart.
#
# Each mark terminates a branch of its own, always entering horizontally
# from the left. They continue the box numbering at 27.
#
# Positions are solved rather than eyeballed, against the spacing the
# traced art keeps: no junction closer than 30 px to a corner of the
# stroke it joins or to another junction on it (the art's own minimum is
# 28.9), no branch under 25 px (its shortest stroke is 22.4), nothing
# crossed, and 22 px clear of any horizontal running alongside. Each
# glyph sits at the nearest point to the design mock (no longer in the repo) that satisfies all
# of it.
#
# 28 moved furthest from the mock: at that height the parent vertical
# carries a junction at y=494.5 and ends at y=553.1, leaving no 30 px
# window between the two. It hangs off the trunk instead.
#
# Branches are authored ending on the notional box edge (box_side / 2
# from the centre); clear_stems then pulls them back to the glyph's own
# reach, exactly as it does for a tick or a cross.
# ================================================================

info_boxes <- rbind(       # x, y
  c(568.5, 295.5),         # 27
  c(700.0, 505.0),         # 28
  c(709.3, 727.0)          # 29
)

info_h <- rbind(           # y, x0, x1   (all fed from the left)
  c(295.5, 522.8, 554.7),  # 27, off V x=522.8
  c(505.0, 649.7, 686.2),  # 28, off V x=649.7
  c(727.0, 649.7, 695.5)   # 29, off V x=649.7
)

# ----------------------------------------------------------------
# Edits to the traced geometry
#
# Kept here rather than in tree_paths.R, which is generated and must stay
# a faithful record of the trace. These are deliberate design changes made
# on top of it.
#
# The branch feeding box 14 is shortened and its corner raised 39.5 px,
# from y=494.5 to y=455. That clears the pocket between V x=649.7 and
# V x=721.5, which info 28 now occupies: at its old height the #14 stem
# ran straight through where the glyph sits.
# ----------------------------------------------------------------

TREE_EDIT_CORNER <- 455.0

edit_traced_v <- function(v) {
  k <- which(abs(v[, 1] - 689.6) < 0.5 & abs(v[, 3] - 494.5) < 0.5)
  stopifnot(length(k) == 1)
  v[k, 3] <- TREE_EDIT_CORNER
  v
}

edit_traced_h <- function(h) {
  k <- which(abs(h[, 1] - 494.5) < 0.5 & abs(h[, 2] - 649.7) < 0.5)
  stopifnot(length(k) == 1)
  h[k, 1] <- TREE_EDIT_CORNER
  h
}
