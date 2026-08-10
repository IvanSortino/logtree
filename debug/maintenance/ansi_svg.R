# Shared ANSI -> SVG renderer for the documentation figures.
#
# Neither GitHub's README renderer nor pkgdown's article chunks emit ANSI, so
# every figure that has to show logtree's *real* colors is a rendered SVG of
# captured console output. This file holds the machinery; the scripts that
# source it supply the run to capture and the callouts to draw.
#
#   readme_tree_svg.R   -> man/figures/README-tree-color.svg
#   article_svg.R       -> man/figures/timestamp-silver.svg,
#                          man/figures/routed-conditions.svg
#
# Tree connectors (rails/branches/corners) are drawn as real SVG <line>
# strokes -- continuous vector lines -- rather than stacking the box-drawing
# glyphs row by row as text, which left them looking like separate dashes
# instead of one connected line. Status glyphs and message text stay as
# monospace <text>/<tspan>, not <foreignObject>, since <img>-embedded SVGs
# generally don't render foreignObject content.

# Fixed palette cli actually emits for these SGR codes (see
# cli::ansi_html_style()), remapped to GitHub's light-theme accents so they
# read on a white background.
palette <- c(
  "30" = "#8b949e", # black/silver (the timestamp column: cli emits 90)
  "31" = "#cf222e", # red     (error)
  "32" = "#1a7f37", # green   (success)
  "33" = "#9a6700", # yellow  (warning)
  "34" = "#0969da", # blue    (info)
  "35" = "#8250df", # magenta (group)
  "36" = "#1b7c83"  # cyan    (step)
)
# Bright (90-97) aliases: cli emits these for the bright variant of a base
# color; the 8th-place offset maps each back to its 30-series base code.
bright_map <- c("90" = "30", "91" = "31", "92" = "32", "93" = "33",
                "94" = "34", "95" = "35", "96" = "36", "97" = "37")
dim_color     <- "#8b949e" # faint (tree connectors)
default_color <- "#24292f" # no color code (message text)
bg_color      <- "#ffffff"
border_color  <- "#d0d7de"
guide_color   <- "#d0d7de"

esc_xml <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  x
}

# Matches full SGR sequences with any number of ';'-separated params,
# e.g. \033[m, \033[0m, \033[1;32m, \033[38;5;40m, \033[38;2;R;G;Bm.
sgr_re <- "\033\\[[0-9;]*m"

# Given the numeric parameters of one SGR sequence (an integer vector),
# apply them in order and return updated (fg, faint). Handles reset,
# faint on/off, default-fg, 30/90-series named colors, and the extended
# 38;5;N (256-color) / 38;2;R;G;B (truecolor -> nearest named) forms.
apply_sgr <- function(codes, fg, faint) {
  i <- 1L
  n <- length(codes)
  while (i <= n) {
    code <- codes[[i]]
    if (code == 0L) {
      fg <- NA_character_; faint <- FALSE
    } else if (code == 2L) {
      faint <- TRUE
    } else if (code == 22L) {
      faint <- FALSE
    } else if (code == 39L) {
      fg <- NA_character_
    } else if (code == 38L) {
      # Extended color: 38;5;N (256-color) or 38;2;R;G;B (truecolor).
      # cli interpolates its palette into the 6x6x6 cube under 256 colors,
      # so we decode the actual RGB and snap to the nearest palette entry
      # rather than relying on fixed cube indices.
      mode <- if (i + 1L <= n) codes[[i + 1L]] else NA_integer_
      if (!is.na(mode) && mode == 5L && i + 2L <= n) {
        rgb <- xterm256_rgb(codes[[i + 2L]])
        fg <- nearest_palette(rgb[1], rgb[2], rgb[3])
        i <- i + 2L
      } else if (!is.na(mode) && mode == 2L && i + 4L <= n) {
        fg <- nearest_palette(codes[[i + 2L]], codes[[i + 3L]], codes[[i + 4L]])
        i <- i + 4L
      }
    } else {
      key <- as.character(code)
      if (key %in% names(bright_map)) key <- bright_map[[key]]
      if (key %in% names(palette)) fg <- palette[[key]]
    }
    i <- i + 1L
  }
  list(fg = fg, faint = faint)
}

# Decode an xterm-256 palette index to an 8-bit RGB triple.
#   0-15    the base 16 ANSI colors (standard + bright)
#   16-231  6x6x6 color cube: 16 + 36*r + 6*g + b, each level in {0..5}
#   232-255 24-step grayscale ramp
xterm256_rgb <- function(idx) {
  base16 <- rbind(
    c(0,0,0), c(205,0,0), c(0,205,0), c(205,205,0),
    c(0,0,238), c(205,0,205), c(0,205,205), c(229,229,229),
    c(127,127,127), c(255,0,0), c(0,255,0), c(255,255,0),
    c(92,92,255), c(255,0,255), c(0,255,255), c(255,255,255)
  )
  if (idx <= 15L) return(base16[idx + 1L, ])
  if (idx >= 232L) { v <- 8L + (idx - 232L) * 10L; return(c(v, v, v)) }
  n <- idx - 16L
  lv <- c(0L, 95L, 135L, 175L, 215L, 255L)  # cli's cube level ramp
  c(lv[(n %/% 36L) %% 6L + 1L],
    lv[(n %/% 6L)  %% 6L + 1L],
    lv[ n          %% 6L + 1L])
}

# Nearest palette entry (plus dim/default grays) by RGB distance. For a
# clearly chromatic input we exclude the near-gray targets so a saturated
# color never snaps to the message/connector gray.
nearest_palette <- function(r, g, b) {
  targets <- c(palette, faint = dim_color, default = default_color)
  chroma <- max(r, g, b) - min(r, g, b)
  if (chroma >= 40L) targets <- palette
  hex2rgb <- function(h) {
    c(strtoi(substr(h, 2, 3), 16L),
      strtoi(substr(h, 4, 5), 16L),
      strtoi(substr(h, 6, 7), 16L))
  }
  d <- vapply(targets, function(h) {
    v <- hex2rgb(h)
    (v[1] - r)^2 + (v[2] - g)^2 + (v[3] - b)^2
  }, numeric(1))
  targets[[which.min(d)]]
}

parse_ansi_line <- function(line) {
  m <- gregexpr(sgr_re, line)[[1]]
  if (m[1] == -1L) return(list(list(text = line, color = default_color)))
  lens <- attr(m, "match.length")
  segs <- list()
  fg <- NA_character_
  faint <- FALSE
  pos <- 1L
  flush <- function(end) {
    if (end >= pos) {
      txt <- substr(line, pos, end)
      col <- if (faint) dim_color else if (!is.na(fg)) fg else default_color
      segs[[length(segs) + 1L]] <<- list(text = txt, color = col)
    }
  }
  for (k in seq_along(m)) {
    start <- m[k]
    flush(start - 1L)
    seq_str <- substr(line, start, start + lens[k] - 1L)
    # Extract the parameter body between "\033[" and "m".
    body <- gsub("^\033\\[|m$", "", seq_str)
    parts <- if (nzchar(body)) strsplit(body, ";", fixed = TRUE)[[1]] else "0"
    codes <- suppressWarnings(as.integer(parts))
    codes[is.na(codes)] <- 0L   # empty params (e.g. "38;;5") default to 0
    st <- apply_sgr(codes, fg, faint)
    fg <- st$fg
    faint <- st$faint
    pos <- start + lens[k]
  }
  flush(nchar(line))
  segs
}

strip_ansi <- function(line) gsub(sgr_re, "", line)

# Slice one line's colored segments to the character range [from, to), 0-based
# and half-open, so a line can be split into its lead column, its connector
# prefix (dropped: drawn as vector lines) and its content.
slice_segs <- function(segs, from, to) {
  pos <- 0L
  kept <- list()
  for (seg in segs) {
    seg_len <- nchar(seg$text)
    start <- pos
    end <- pos + seg_len
    pos <- end
    if (end <= from || start >= to) next
    lo <- max(start, from) - start
    hi <- min(end, to) - start
    kept[[length(kept) + 1L]] <- list(text = substr(seg$text, lo + 1L, hi),
                                      color = seg$color)
  }
  kept
}

# Render captured ANSI console output to an SVG file.
#
#   ansi_lines  character vector, one element per console line, ANSI intact
#   out_path    where to write
#   annotations list of list(match =, color =, text =): a faint dotted guide
#               from the first row whose plain text contains `match`, out to a
#               short label in the right gutter
#   lead        number of leading plain characters that sit *before* the tree
#               (the timestamp column). Drawn as text; the connector scan and
#               every column position shift right by it.
ansi_svg_write <- function(ansi_lines, out_path, annotations = list(),
                           lead = 0L, title = "logtree console output",
                           label = "Colorized logtree console output") {
  parsed <- lapply(ansi_lines, parse_ansi_line)
  plain  <- vapply(ansi_lines, strip_ansi, character(1))

  # Every prefix unit -- rail_unit() and connector_str() alike -- is exactly
  # 3 characters wide ("|  ", "|- ", "`- "), so the prefix is always a whole
  # multiple of 3 chars, and it is matched cell by cell rather than character
  # by character: matching single characters would read the leading "── " of
  # logtree_summary()'s cli::rule() as a rail unit and open a column that
  # never closes, drawing a stray vertical line from the rule down to the
  # foot of the figure.
  prefix_units <- c("│  ", "├─ ", "└─ ", "   ")
  prefix_len <- function(line) {
    n <- 0L
    repeat {
      cell <- substr(line, lead + n + 1L, lead + n + 3L)
      if (!(cell %in% prefix_units)) break
      n <- n + 3L
    }
    n
  }
  prefix_lens <- vapply(plain, prefix_len, integer(1))

  font_size   <- 13
  line_height <- 19
  char_width  <- 7.85
  pad_x       <- 20
  pad_top     <- 16
  pad_bottom  <- 16

  max_chars  <- max(nchar(plain, type = "chars"))
  tree_width <- ceiling(pad_x * 2 + max_chars * char_width)
  height     <- ceiling(pad_top + length(ansi_lines) * line_height +
                          pad_bottom - (line_height - font_size))

  row_top <- function(i) pad_top + (i - 1L) * line_height
  row_mid <- function(i) row_top(i) + line_height / 2
  row_bot <- function(i) row_top(i) + line_height
  col_x   <- function(u) pad_x + (lead + u * 3) * char_width
  col_center <- function(u) col_x(u) + char_width / 2
  # Stops after the dash char (unit's 2nd char), leaving its 3rd (space)
  # char as a gap before the glyph -- same gap the plain-text tree has.
  stub_end   <- function(u) col_x(u) + 2 * char_width

  # Walk the prefix of every line unit-by-unit (each unit = 3 chars: pipe,
  # branch, or corner). A pipe or branch keeps a column's vertical run open (a
  # branch also gets a horizontal stub to the right); a corner closes the run
  # at half the row's height -- it turns right instead of continuing down.
  active <- list()
  v_segs <- list()
  h_segs <- list()
  for (i in seq_along(plain)) {
    nunits <- prefix_lens[[i]] %/% 3L
    if (nunits > 0L) {
      for (u in 0:(nunits - 1L)) {
        cell <- substr(plain[[i]], lead + u * 3L + 1L, lead + u * 3L + 3L)
        fc <- substr(cell, 1L, 1L)
        key <- as.character(u)
        if (fc == "└") {
          start <- if (!is.null(active[[key]])) active[[key]] else i
          v_segs[[length(v_segs) + 1L]] <- list(unit = u, start = start,
                                                end = i, half = TRUE)
          active[[key]] <- NULL
          h_segs[[length(h_segs) + 1L]] <- list(unit = u, row = i)
        } else {
          if (is.null(active[[key]])) active[[key]] <- i
          if (fc == "├") h_segs[[length(h_segs) + 1L]] <- list(unit = u, row = i)
        }
      }
    }
  }
  for (key in names(active)) {
    v_segs[[length(v_segs) + 1L]] <- list(unit = as.integer(key),
                                          start = active[[key]],
                                          end = length(plain), half = FALSE)
  }

  vline_svg <- vapply(v_segs, function(s) {
    y2 <- if (s$half) row_mid(s$end) else row_bot(s$end)
    sprintf('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1.5" stroke-linecap="round"/>',
            col_center(s$unit), row_top(s$start), col_center(s$unit), y2, dim_color)
  }, character(1))

  hline_svg <- vapply(h_segs, function(s) {
    sprintf('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1.5" stroke-linecap="round"/>',
            col_center(s$unit), row_mid(s$row), stub_end(s$unit), row_mid(s$row), dim_color)
  }, character(1))

  # Two text runs per line: the lead column (drawn at the left margin) and the
  # content past the connector prefix. The prefix itself becomes the vector
  # lines above, computed straight from the plain characters, not segments.
  text_svg <- character(0)
  as_tspans <- function(segs) {
    paste(vapply(segs, function(s) {
      sprintf('<tspan fill="%s">%s</tspan>', s$color, esc_xml(s$text))
    }, character(1)), collapse = "")
  }
  for (i in seq_along(parsed)) {
    y <- pad_top + (i - 1L) * line_height + font_size
    if (lead > 0L) {
      spans <- as_tspans(slice_segs(parsed[[i]], 0L, lead))
      if (nzchar(spans)) {
        text_svg <- c(text_svg, sprintf(
          '<text x="%.2f" y="%s" xml:space="preserve">%s</text>', pad_x, y, spans))
      }
    }
    plen <- lead + prefix_lens[[i]]
    spans <- as_tspans(slice_segs(parsed[[i]], plen, nchar(plain[[i]])))
    if (nzchar(spans)) {
      text_svg <- c(text_svg, sprintf(
        '<text x="%.2f" y="%s" xml:space="preserve">%s</text>',
        pad_x + plen * char_width, y, spans))
    }
  }

  # --- annotations: color-coded right-gutter callouts ------------------------
  # Each callout points a faint dotted guide from one matched tree row to a
  # short label rendered in that feature's own accent color, so the label reads
  # as an explanation of the glyph it lines up with. Keyed by a unique
  # substring of the (plain, ANSI-stripped) row text so it survives layout
  # tweaks.
  ann_font <- 11
  ann_char <- 6.1                       # approx label glyph width (sans, 11px)
  ann_x    <- tree_width + 40           # label column start, past the tree

  ann_svg <- character(0)
  for (a in annotations) {
    hits <- which(vapply(plain, function(p) grepl(a$match, p, fixed = TRUE), logical(1)))
    # `nth` picks a later occurrence, for the case where the point being made
    # is precisely that the same text appears twice (a group header that
    # recurs non-adjacently, say) and the first hit is the wrong row.
    i <- hits[if (is.null(a$nth)) 1L else a$nth]
    if (is.na(i)) next
    y  <- row_mid(i)
    x0 <- pad_x + nchar(plain[[i]]) * char_width + 8   # just past this row's text
    x1 <- ann_x - 10
    ann_svg <- c(ann_svg,
      sprintf('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1" stroke-dasharray="1 3"/>',
              x0, y, x1, y, guide_color),
      sprintf('<circle cx="%.2f" cy="%.2f" r="2" fill="%s"/>', x1 + 4, y, a$color),
      sprintf('<text x="%.2f" y="%.2f" fill="%s">%s</text>', ann_x, y + ann_font / 3, a$color, esc_xml(a$text)))
  }

  width <- if (length(annotations)) {
    max_label <- max(vapply(annotations, function(a) nchar(a$text), integer(1)))
    ceiling(ann_x + max_label * ann_char + pad_x)
  } else {
    tree_width
  }

  svg <- paste0(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', width, ' ', height,
    '" width="', width, '" height="', height,
    '" role="img" aria-label="', label, '">\n',
    '<title>', title, '</title>\n',
    '<rect x="0.5" y="0.5" width="', width - 1, '" height="', height - 1,
    '" rx="8" fill="', bg_color, '" stroke="', border_color, '"/>\n',
    '<g stroke-linecap="round">\n', paste(vline_svg, collapse = "\n"), "\n",
    paste(hline_svg, collapse = "\n"), '\n</g>\n',
    '<g font-family="ui-monospace, SFMono-Regular, &quot;SF Mono&quot;, Menlo, Consolas, monospace" font-size="', font_size, '">\n',
    paste(text_svg, collapse = "\n"), '\n</g>\n',
    '<g font-family="-apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif" font-size="', ann_font, '">\n',
    paste(ann_svg, collapse = "\n"), '\n</g>\n',
    '</svg>\n'
  )

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(svg, out_path)
  cat("wrote", out_path, "(", width, "x", height, ")\n")
  invisible(list(width = width, height = height))
}

# --- anatomy figures ---------------------------------------------------------

# Render ONE captured line and label the columns it is built from.
#
# Unlike ansi_svg_write(), the connector prefix is drawn as text rather than as
# vector strokes: a single line has no vertical runs to join up, and the point
# of this figure is that the connector *occupies character cells*, which is
# exactly what the bracket beneath it has to measure.
#
#   ansi_line  one console line, ANSI intact
#   columns    list of list(from =, to =, label =, color =): character offsets
#              into the plain (ANSI-stripped) line, 0-based and half-open.
#              Brackets are drawn under [from, to) and labelled on staggered
#              rows, left to right, so adjacent labels cannot collide.
ansi_svg_anatomy <- function(ansi_line, out_path, columns,
                             title = "Anatomy of a logtree line",
                             label = "The columns of one rendered logtree line") {
  segs  <- parse_ansi_line(ansi_line)
  plain <- strip_ansi(ansi_line)

  font_size   <- 14
  char_width  <- 8.45
  pad_x       <- 24
  pad_top     <- 22
  line_y      <- pad_top + font_size
  bracket_y   <- line_y + 12
  row_step    <- 21
  ann_font    <- 12
  ann_char    <- 6.6

  col_x <- function(ch) pad_x + ch * char_width

  # Label rows descend left to right, so a short column and its neighbour
  # never land on the same baseline.
  ord <- order(vapply(columns, function(c) c$from, numeric(1)))
  row_of <- integer(length(columns))
  row_of[ord] <- seq_along(ord)

  bracket_svg <- character(0)
  label_svg   <- character(0)
  for (k in seq_along(columns)) {
    cc <- columns[[k]]
    x0 <- col_x(cc$from)
    x1 <- col_x(cc$to)
    xm <- (x0 + x1) / 2
    y  <- bracket_y
    ylab <- bracket_y + row_of[[k]] * row_step
    col <- if (is.null(cc$color)) default_color else cc$color
    # bracket: a short tick down at each end joined by a horizontal run
    bracket_svg <- c(bracket_svg, sprintf(
      '<path d="M %.2f %.2f L %.2f %.2f L %.2f %.2f L %.2f %.2f" fill="none" stroke="%s" stroke-width="1.2"/>',
      x0, y - 4, x0, y, x1, y, x1, y - 4, col))
    # leader from the bracket's midpoint down to its label row
    bracket_svg <- c(bracket_svg, sprintf(
      '<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1" stroke-dasharray="1 3"/>',
      xm, y, xm, ylab - 8, col))
    # A label sits on the row it was staggered onto, but the leaders of the
    # columns to its right run straight down through that row. Painting an
    # opaque plate under each label -- and drawing every label after every
    # leader -- keeps the text legible where they cross.
    lab_w <- nchar(cc$label) * ann_char
    label_svg <- c(label_svg, sprintf(
      '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',
      xm + 3, ylab - ann_font + 1, lab_w + 12, ann_font + 5, bg_color))
    label_svg <- c(label_svg, sprintf(
      '<circle cx="%.2f" cy="%.2f" r="2" fill="%s"/>', xm, ylab - 4, col))
    label_svg <- c(label_svg, sprintf(
      '<text x="%.2f" y="%.2f" fill="%s">%s</text>',
      xm + 7, ylab, col, esc_xml(cc$label)))
  }

  text_spans <- paste(vapply(segs, function(s) {
    sprintf('<tspan fill="%s">%s</tspan>', s$color, esc_xml(s$text))
  }, character(1)), collapse = "")

  widest_label <- max(vapply(seq_along(columns), function(k) {
    cc <- columns[[k]]
    (col_x(cc$from) + col_x(cc$to)) / 2 + 7 + nchar(cc$label) * ann_char
  }, numeric(1)))
  width  <- ceiling(max(pad_x * 2 + nchar(plain) * char_width, widest_label + pad_x))
  height <- ceiling(bracket_y + length(columns) * row_step + 18)

  svg <- paste0(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', width, ' ', height,
    '" width="', width, '" height="', height,
    '" role="img" aria-label="', label, '">\n',
    '<title>', title, '</title>\n',
    '<rect x="0.5" y="0.5" width="', width - 1, '" height="', height - 1,
    '" rx="8" fill="', bg_color, '" stroke="', border_color, '"/>\n',
    '<g font-family="ui-monospace, SFMono-Regular, &quot;SF Mono&quot;, Menlo, Consolas, monospace" font-size="', font_size, '">\n',
    sprintf('<text x="%.2f" y="%s" xml:space="preserve">%s</text>', pad_x, line_y, text_spans),
    '\n</g>\n',
    '<g>\n', paste(bracket_svg, collapse = "\n"), '\n</g>\n',
    '<g font-family="-apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif" font-size="', ann_font, '">\n',
    paste(label_svg, collapse = "\n"), '\n</g>\n',
    '</svg>\n'
  )

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(svg, out_path)
  cat("wrote", out_path, "(", width, "x", height, ")\n")
  invisible(list(width = width, height = height))
}


# --- frame-lifetime figure ---------------------------------------------------

# A two-panel diagram: an execution trace on the left, the line logtree printed
# at that moment on the right, and vertical bars showing how long each
# function's *frame* lives.
#
# The rows are runtime events in the order they happen, not source lines. That
# distinction is the whole point: a frame's lifetime is an interval in time, so
# bars drawn over source lines would only mark out function bodies, which
# explains nothing. Laid out as a trace, the bars line up with the rows where
# the close lines appear -- and those rows carry no log_*() call at all, which
# is exactly the thing output alone cannot show.
#
# Rows align 1:1 across the two panels, so no leader lines are needed; pad
# `tree_rows` with "" wherever a runtime event prints nothing.
#
#   trace_rows  character vector, the execution trace (plain text, no ANSI)
#   tree_rows   character vector of the same length, ANSI intact, "" for none
#   frames      list of list(start =, end =, label =, color =, depth =):
#               1-based inclusive row indices, depth insetting nested frames
frames_svg_write <- function(trace_rows, tree_rows, frames, out_path,
                             title = "How a step knows when to close",
                             label = "An execution trace beside the logtree output it produces, with bars showing each function frame's lifetime") {
  stopifnot(length(trace_rows) == length(tree_rows))
  parsed <- lapply(tree_rows, function(l) if (nzchar(l)) parse_ansi_line(l) else list())
  plain  <- vapply(tree_rows, strip_ansi, character(1))

  font_size   <- 13
  line_height <- 22
  char_width  <- 7.85
  pad_x       <- 20
  pad_top     <- 34
  bar_w       <- 4
  bar_gap     <- 9
  hdr_font    <- 11
  leg_font    <- 11

  max_depth <- max(vapply(frames, function(f) f$depth, numeric(1)))
  gutter_w  <- (max_depth + 1) * bar_gap + 8
  trace_x   <- pad_x + gutter_w
  trace_w   <- max(nchar(trace_rows)) * char_width
  panel_gap <- 46
  tree_x    <- trace_x + trace_w + panel_gap
  tree_w    <- max(nchar(plain)) * char_width
  width     <- ceiling(tree_x + tree_w + pad_x)
  n_rows    <- length(trace_rows)
  legend_h  <- 26
  height    <- ceiling(pad_top + n_rows * line_height + legend_h + 10)

  row_y   <- function(i) pad_top + (i - 1L) * line_height + font_size
  row_mid <- function(i) pad_top + (i - 1L) * line_height + line_height / 2

  # One rounded bar per frame, spanning the rows between the call that opened
  # it and the return that closed it, inset by depth so nesting reads as depth.
  bar_svg <- character(0)
  for (f in frames) {
    x  <- pad_x + f$depth * bar_gap
    y0 <- row_mid(f$start) - line_height / 2 + 3
    y1 <- row_mid(f$end) + line_height / 2 - 3
    bar_svg <- c(bar_svg, sprintf(
      '<rect x="%.2f" y="%.2f" width="%d" height="%.2f" rx="%.1f" fill="%s" opacity="0.9"/>',
      x, y0, bar_w, y1 - y0, bar_w / 2, f$color))
  }

  trace_svg <- vapply(seq_along(trace_rows), function(i) {
    if (!nzchar(trace_rows[[i]])) return("")
    # A row that is a comment (a return, not a call) reads as supporting text.
    col <- if (grepl("^\\s*#", trace_rows[[i]])) dim_color else default_color
    sprintf('<text x="%.2f" y="%.2f" fill="%s" xml:space="preserve">%s</text>',
            trace_x, row_y(i), col, esc_xml(trace_rows[[i]]))
  }, character(1))

  tree_svg <- vapply(seq_along(parsed), function(i) {
    if (!length(parsed[[i]])) return("")
    spans <- paste(vapply(parsed[[i]], function(s) {
      sprintf('<tspan fill="%s">%s</tspan>', s$color, esc_xml(s$text))
    }, character(1)), collapse = "")
    sprintf('<text x="%.2f" y="%.2f" xml:space="preserve">%s</text>',
            tree_x, row_y(i), spans)
  }, character(1))

  hdr_svg <- c(
    sprintf('<text x="%.2f" y="%d" fill="%s">%s</text>', trace_x, 18, dim_color,
            "what runs, in order"),
    sprintf('<text x="%.2f" y="%d" fill="%s">%s</text>', tree_x, 18, dim_color,
            "what logtree prints")
  )

  leg_y <- pad_top + n_rows * line_height + 16
  leg_x <- trace_x
  leg_svg <- character(0)
  for (f in frames) {
    leg_svg <- c(leg_svg, sprintf(
      '<rect x="%.2f" y="%.2f" width="%d" height="10" rx="2" fill="%s"/>',
      leg_x, leg_y - 8, bar_w, f$color))
    leg_svg <- c(leg_svg, sprintf(
      '<text x="%.2f" y="%.2f" fill="%s">%s</text>',
      leg_x + 10, leg_y, dim_color, esc_xml(paste0(f$label, " frame"))))
    leg_x <- leg_x + 10 + nchar(paste0(f$label, " frame")) * 6.2 + 22
  }

  svg <- paste0(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', width, ' ', height,
    '" width="', width, '" height="', height,
    '" role="img" aria-label="', label, '">\n',
    '<title>', title, '</title>\n',
    '<rect x="0.5" y="0.5" width="', width - 1, '" height="', height - 1,
    '" rx="8" fill="', bg_color, '" stroke="', border_color, '"/>\n',
    '<g>\n', paste(bar_svg, collapse = "\n"), '\n</g>\n',
    '<g font-family="-apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif" font-size="', hdr_font, '">\n',
    paste(hdr_svg, collapse = "\n"), '\n</g>\n',
    '<g font-family="ui-monospace, SFMono-Regular, &quot;SF Mono&quot;, Menlo, Consolas, monospace" font-size="', font_size, '">\n',
    paste(c(trace_svg, tree_svg), collapse = "\n"), '\n</g>\n',
    '<g font-family="-apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Helvetica, Arial, sans-serif" font-size="', leg_font, '">\n',
    paste(leg_svg, collapse = "\n"), '\n</g>\n',
    '</svg>\n'
  )

  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(svg, out_path)
  cat("wrote", out_path, "(", width, "x", height, ")\n")
  invisible(list(width = width, height = height))
}
