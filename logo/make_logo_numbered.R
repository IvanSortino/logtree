# ================================================================
# logtree — numbered map of the terminal marks
#
# Output: logo/logo_numbered.png
#
# A working aid, not artwork: the same tree with every terminal mark
# labelled, so one can be named by number when deciding which becomes a
# tick or a cross. Feed those numbers to box_style in
# make_logo_traced.R.
#
# 1-26 are the traced boxes, in amber. 27 up are the authored info
# marks, in blue, drawn with the branches that carry them. Numbering is
# fixed by tree_paths.R for the boxes and by info_marks.R for the info
# marks, so the numbers do not move unless the geometry is regenerated.
#
# Every mark is drawn as a plain square here whatever it renders as in
# the finished logo — the point is to read the number, not the glyph.
#
# Dependencies: grid, ragg
# ================================================================

library(grid)

root <- if (dir.exists("logo")) "." else ".."
OUT  <- file.path(root, "logo", "logo_numbered.png")

source(file.path(root, "logo", "tree_paths.R"))
source(file.path(root, "logo", "info_marks.R"))

HEIGHT <- 1200L
WIDTH  <- round(HEIGHT * sqrt(3) / 2)
DPI    <- 600

BG          <- "#21113D"
HEX_BORDER  <- "#7540B8"
TREE_COLOR  <- "#AE87E6"
INFO_COLOR  <- "#57A1E4"
LABEL_COL   <- "#FFD166"

HEX_PX    <- 22
BRANCH_PX <- 7

lw <- function(px) px * 96 / DPI
pt <- function(px) px * 72 / DPI

nx <- function(x) x / WIDTH
ny <- function(y) 1 - y / HEIGHT

dir.create(dirname(OUT), recursive = TRUE, showWarnings = FALSE)

ragg::agg_png(filename = OUT, width = WIDTH, height = HEIGHT,
              units = "px", res = DPI, background = "transparent")
grid.newpage()

angles <- seq(90, 90 + 300, by = 60) * pi / 180
r <- HEIGHT / 2 - HEX_PX / 2
grid.polygon(
  x = 0.5 + r * cos(angles) / WIDTH,
  y = 0.5 + r * sin(angles) / HEIGHT,
  default.units = "npc",
  gp = gpar(fill = BG, col = HEX_BORDER, lwd = lw(HEX_PX),
            linejoin = "mitre")
)

gp <- gpar(col = TREE_COLOR, lwd = lw(BRANCH_PX), lineend = "round",
           linejoin = "round")
all_v <- edit_traced_v(tree_v)
for (i in seq_len(nrow(all_v))) {
  s <- all_v[i, ]
  grid.lines(x = nx(c(s[1], s[1])), y = ny(c(s[2], s[3])),
             default.units = "npc", gp = gp)
}
all_h <- rbind(edit_traced_h(tree_h), info_h)
for (i in seq_len(nrow(all_h))) {
  s <- all_h[i, ]
  grid.lines(x = nx(c(s[2], s[3])), y = ny(c(s[1], s[1])),
             default.units = "npc", gp = gp)
}

# Boxes 1-26 then info marks 27 up, numbered straight through.
marks <- rbind(tree_boxes, info_boxes)
cols  <- c(rep(TREE_COLOR, nrow(tree_boxes)),
           rep(INFO_COLOR, nrow(info_boxes)))

h <- box_side / 2
for (i in seq_len(nrow(marks))) {
  cx <- marks[i, 1]
  cy <- marks[i, 2]
  grid.polygon(
    x = nx(cx + c(-h, h, h, -h)),
    y = ny(cy + c(-h, -h, h, h)),
    default.units = "npc",
    gp = gpar(col = cols[i], fill = NA, lwd = lw(BRANCH_PX),
              linejoin = "round")
  )
  # Label sits inside the box; the box is 27.6 px so two digits fit.
  grid.text(
    i,
    x = nx(cx), y = ny(cy),
    default.units = "npc",
    gp = gpar(col = LABEL_COL, fontsize = pt(17), fontface = "bold")
  )
}

dev.off()

message("Created: ", normalizePath(OUT))
message("Marks: ", nrow(tree_boxes), " boxes (1-", nrow(tree_boxes), "), ",
        nrow(info_boxes), " info (", nrow(tree_boxes) + 1, "-",
        nrow(marks), ")")
