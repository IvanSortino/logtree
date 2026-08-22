# ================================================================
# logtree — the hex sticker
#
# Output: logo/logo.png
#
# Geometry comes from two data files, both in canvas coordinates:
#   tree_paths.R   the tree, and the 26 terminal boxes
#   info_marks.R   the 3 info marks, their branches, and one edit to the
#                  traced geometry
#
# Terminal boxes are objects rather than loose strokes, so any one of
# them can render as a square, a tick, a cross or an info mark. Set that
# per box in box_style below, using the numbers on the map that
# make_logo_numbered.R draws.
#
# Canvas is a true hex box: 1039 x 1200, hexagon touching all four edges.
#
# Dependencies: grid, ragg, systemfonts
# ================================================================

library(grid)

root <- if (dir.exists("logo")) "." else ".."

OUT  <- file.path(root, "logo", "logo.png")

source(file.path(root, "logo", "tree_paths.R"))

# ----------------------------------------------------------------
# Which boxes carry a symbol. Everything unnamed stays a square.
# ----------------------------------------------------------------

box_style <- rep("square", nrow(tree_boxes))
box_style[c(7, 8)]  <- "tick"
box_style[c(9, 13)] <- "cross"

# The info marks and their branches are authored geometry, kept in their
# own file so regenerating the trace cannot clobber them, and shared with
# the numbered map. They continue the box numbering at 27.
source(file.path(root, "logo", "info_marks.R"))

all_boxes <- rbind(tree_boxes, info_boxes)
all_style <- c(box_style, rep("info", nrow(info_boxes)))
all_v <- edit_traced_v(tree_v)
all_h <- rbind(edit_traced_h(tree_h), info_h)

HEIGHT <- 1200L
WIDTH  <- round(HEIGHT * sqrt(3) / 2)
DPI    <- 600

BG          <- "#21113D"
HEX_BORDER  <- "#7540B8"
TREE_COLOR  <- "#AE87E6"
TICK_COLOR  <- "#50B97C"
CROSS_COLOR <- "#C94364"
INFO_COLOR  <- "#57A1E4"

HEX_PX    <- 22
BRANCH_PX <- 7          # source strokes are 6 px at 1024, x1.202
MARK_PX   <- 10         # tick and cross are drawn heavier than the tree

# Symbol geometry is written at the size drawn on the original design
# mock and then scaled: round caps add half a stroke at each end, so the
# polyline has to come in for the glyph to match. The scale is set against
# the stroke — thinning it without opening the polyline would shrink
# the whole glyph rather than just slimming it.
MARK_SCALE <- 0.89
MARK_GAP   <- 8         # clear space between a symbol and its branch

lw <- function(px) px * 96 / DPI
pt <- function(px) px * 72 / DPI

# ----------------------------------------------------------------
# Wordmark
#
# IBM Plex Sans Medium. Chosen by measurement against the original art,
# whose lettering runs a stem 0.197 of its x-height; Medium comes out at
# 0.189, the nearest of the weights tried.
#
# The face is registered from a file in the repo rather than taken from
# the system, so the render does not depend on what happens to be
# installed. Without that, grid substitutes silently and the wordmark
# changes shape from machine to machine. IBM Plex Sans is SIL OFL, so
# shipping it here is fine — the licence sits beside it.
#
# To render another weight, change all four values together. They are
# not independent: each face has its own em size, side bearing, and
# baseline position within the line box. These were solved by rendering
# and measuring, so that every one puts the wordmark ink 430 px wide
# with its left edge at x=80 and its baseline at y=628 — the placement
# measured off the original design mock.
#
#   face                      WM_SIZE  WM_LEFT  WM_BOTTOM  stem/x-height
#   IBMPlexSans-Regular.ttf     141.7       68        627          0.147
#   IBMPlexSans-Medium.ttf      138.3       69        627          0.189
#   IBMPlexSans-SemiBold.ttf    135.9       70        627          0.236
#
# To solve a face that is not listed: render, measure the white ink,
# then correct WM_SIZE by 430/width, WM_LEFT by 80-left, and WM_BOTTOM
# by 628-baseline. Repeat until it settles — three passes is plenty.
# ----------------------------------------------------------------

WM_FILE <- file.path(root, "logo", "fonts", "IBMPlexSans-Medium.ttf")
stopifnot(file.exists(WM_FILE))
systemfonts::register_font(name = "logtree wordmark", plain = WM_FILE)

WORDMARK  <- "logtree"
WM_FONT   <- "logtree wordmark"
WM_COLOR  <- "#FFFFFF"
WM_SIZE   <- 138.3   # px em
WM_LEFT   <- 69      # "left" includes the left side bearing
WM_BOTTOM <- 627     # "bottom" is the descent line, not the ink edge

draw_wordmark <- function() {
  grid.text(
    WORDMARK,
    x = nx(WM_LEFT), y = ny(WM_BOTTOM),
    just = c("left", "bottom"),
    default.units = "npc",
    gp = gpar(col = WM_COLOR, fontsize = pt(WM_SIZE), fontfamily = WM_FONT)
  )
}

# ----------------------------------------------------------------
# Terminal prompt, below the wordmark
#
# Drawn as geometry rather than set as text: the mock's chevron is a
# solid stroke with a mitred apex, not a font's '>', and drawing it
# keeps the prompt free of any font dependency at all.
#
# Traced off the original design mock — chevron ink x[82,147]
# y[666,743], bar ink x[156,222] y[735,748], both about 13 px thick.
# ----------------------------------------------------------------

PROMPT_COLOR <- "#8A52D8"
PROMPT_PX    <- 13

PROMPT_X   <- c(86, 136, 86)     # chevron, left tip -> apex -> left tip
PROMPT_Y   <- c(671, 703, 738)
PROMPT_BAR <- c(156, 222, 741.5)  # bar: x0, x1, y

draw_prompt <- function() {
  grid.lines(
    x = nx(PROMPT_X), y = ny(PROMPT_Y),
    default.units = "npc",
    gp = gpar(col = PROMPT_COLOR, lwd = lw(PROMPT_PX),
              lineend = "butt", linejoin = "mitre")
  )
  grid.lines(
    x = nx(PROMPT_BAR[1:2]), y = ny(rep(PROMPT_BAR[3], 2)),
    default.units = "npc",
    gp = gpar(col = PROMPT_COLOR, lwd = lw(PROMPT_PX), lineend = "butt")
  )
}

# Canvas px (y measured downwards) -> npc.
nx <- function(x) x / WIDTH
ny <- function(y) 1 - y / HEIGHT

draw_hexagon <- function() {
  angles <- seq(90, 90 + 300, by = 60) * pi / 180
  r <- HEIGHT / 2 - HEX_PX / 2
  grid.polygon(
    x = 0.5 + r * cos(angles) / WIDTH,
    y = 0.5 + r * sin(angles) / HEIGHT,
    default.units = "npc",
    gp = gpar(fill = BG, col = HEX_BORDER, lwd = lw(HEX_PX),
              linejoin = "mitre")
  )
}

draw_tree <- function(v, h) {
  # Round caps do the corner work: ends sit exactly on the centreline of
  # the stroke they meet, so a cap of half the stroke width fills the
  # corner and rounds its outside instead of leaving a notch or a tab.
  gp <- gpar(col = TREE_COLOR, lwd = lw(BRANCH_PX), lineend = "round",
             linejoin = "round")

  for (i in seq_len(nrow(v))) {               # x, y0, y1
    s <- v[i, ]
    grid.lines(x = nx(c(s[1], s[1])), y = ny(c(s[2], s[3])),
               default.units = "npc", gp = gp)
  }
  for (i in seq_len(nrow(h))) {               # y, x0, x1
    s <- h[i, ]
    grid.lines(x = nx(c(s[2], s[3])), y = ny(c(s[1], s[1])),
               default.units = "npc", gp = gp)
  }
}

# ----------------------------------------------------------------
# Box glyphs. Offsets are from the box centre, in canvas px, and the
# tick and cross are sized to the proportions of the original mock.
# ----------------------------------------------------------------

draw_square <- function(cx, cy, side) {
  h <- side / 2
  grid.polygon(
    x = nx(cx + c(-h, h, h, -h)),
    y = ny(cy + c(-h, -h, h, h)),
    default.units = "npc",
    gp = gpar(col = TREE_COLOR, fill = NA, lwd = lw(BRANCH_PX),
              linejoin = "round")
  )
}

TICK_X  <- c(-16.5, -6.5, 18.5) * MARK_SCALE
TICK_Y  <- c(3.5, 14.5, -11.5) * MARK_SCALE
CROSS_H <- 13.5 * MARK_SCALE

draw_tick <- function(cx, cy) {
  grid.lines(
    x = nx(cx + TICK_X), y = ny(cy + TICK_Y),
    default.units = "npc",
    gp = gpar(col = TICK_COLOR, lwd = lw(MARK_PX), lineend = "round",
              linejoin = "round")
  )
}

draw_cross <- function(cx, cy) {
  gp <- gpar(col = CROSS_COLOR, lwd = lw(MARK_PX), lineend = "round")
  grid.lines(x = nx(cx + c(-CROSS_H, CROSS_H)),
             y = ny(cy + c(-CROSS_H, CROSS_H)),
             default.units = "npc", gp = gp)
  grid.lines(x = nx(cx + c(-CROSS_H, CROSS_H)),
             y = ny(cy + c(CROSS_H, -CROSS_H)),
             default.units = "npc", gp = gp)
}

# The info mark, traced off the original mock: a dot over a serif "i" —
# top flag, stem, foot serif. Offsets are from the glyph centre.
INFO_R  <- 6      # dot radius
INFO_DY <- -15    # dot centre, above the body
INFO_X  <- c(-9,  4,  4,  8,   8,  -9,  -9,   -5,  -5,  -9)
INFO_Y  <- c(-5.5, -5.5, 14.5, 14.5, 19.5, 19.5, 14.5, 14.5, -0.5, -0.5)

draw_info <- function(cx, cy) {
  gp <- gpar(col = NA, fill = INFO_COLOR)
  grid.circle(x = nx(cx), y = ny(cy + INFO_DY), r = INFO_R / WIDTH,
              default.units = "npc", gp = gp)
  grid.polygon(x = nx(cx + INFO_X), y = ny(cy + INFO_Y),
               default.units = "npc", gp = gp)
}

# How far a finished glyph reaches from the box centre, per direction and
# stroke included. Directional because the tick is not centred on the box:
# it hangs lower than it rises, so one half-range would be wrong on both
# sides at once. The info mark is likewise taller above than below.
mark_reach <- function(style) {
  cap <- MARK_PX / 2
  if (style == "tick") {
    c(up = -min(TICK_Y) + cap, down = max(TICK_Y) + cap,
      left = -min(TICK_X) + cap, right = max(TICK_X) + cap)
  } else if (style == "info") {
    c(up = -(INFO_DY - INFO_R), down = max(INFO_Y),
      left = -min(INFO_X), right = max(INFO_X))
  } else {
    c(up = CROSS_H + cap, down = CROSS_H + cap,
      left = CROSS_H + cap, right = CROSS_H + cap)
  }
}

# Pull back every branch that ran into a symbol. The stem used to stop on
# the square's edge, but a tick or a cross reaches further than the square
# it replaces, so without this the glyph would sit on the line.
clear_stems <- function(v, h) {
  half <- box_side / 2
  # The branch carries a round cap of its own, which reaches half a stroke
  # past its endpoint — count it, or the gap comes out short by that much.
  pad <- MARK_GAP + BRANCH_PX / 2
  for (i in which(all_style != "square")) {
    cx <- all_boxes[i, 1]
    cy <- all_boxes[i, 2]
    reach <- mark_reach(all_style[i])
    for (k in seq_len(nrow(v))) {
      if (abs(v[k, 1] - cx) > half + 1) next
      for (e in 2:3) {
        if (abs(v[k, e] - (cy - half)) < 1.5) {
          v[k, e] <- cy - reach[["up"]] - pad
        } else if (abs(v[k, e] - (cy + half)) < 1.5) {
          v[k, e] <- cy + reach[["down"]] + pad
        }
      }
    }
    for (k in seq_len(nrow(h))) {
      if (abs(h[k, 1] - cy) > half + 1) next
      for (e in 2:3) {
        if (abs(h[k, e] - (cx - half)) < 1.5) {
          h[k, e] <- cx - reach[["left"]] - pad
        } else if (abs(h[k, e] - (cx + half)) < 1.5) {
          h[k, e] <- cx + reach[["right"]] + pad
        }
      }
    }
  }
  list(v = v, h = h)
}

draw_boxes <- function() {
  for (i in seq_len(nrow(all_boxes))) {
    cx <- all_boxes[i, 1]
    cy <- all_boxes[i, 2]
    switch(all_style[i],
           square = draw_square(cx, cy, box_side),
           tick   = draw_tick(cx, cy),
           cross  = draw_cross(cx, cy),
           info   = draw_info(cx, cy),
           stop("unknown box style: ", all_style[i]))
  }
}

dir.create(dirname(OUT), recursive = TRUE, showWarnings = FALSE)

ragg::agg_png(filename = OUT, width = WIDTH, height = HEIGHT,
              units = "px", res = DPI, background = "transparent")
grid.newpage()
draw_hexagon()
adjusted <- clear_stems(all_v, all_h)
draw_tree(adjusted$v, adjusted$h)
draw_boxes()
draw_wordmark()
draw_prompt()
dev.off()

message("Created: ", normalizePath(OUT))
message("Segments: ", nrow(all_v), " vertical, ", nrow(all_h),
        " horizontal")
message("Boxes: ", sum(all_style == "square"), " square, ",
        sum(all_style == "tick"), " tick, ",
        sum(all_style == "cross"), " cross, ",
        sum(all_style == "info"), " info")
