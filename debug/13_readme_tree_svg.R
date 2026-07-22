devtools::load_all()

# Regenerates man/figures/README-tree-color.svg, the colorized companion to
# the plain ```ansi tree in README.Rmd. GitHub strips inline `style` from
# Markdown HTML and doesn't render ANSI in README code blocks, so an <img>
# of a rendered SVG is the only way to show the real theme colors there.
#
# Runs the actual ETL example through with_logging() with a fake clock (so
# elapsed times are deterministic), captures the real ANSI this package
# emits (forcing color via cli.num_colors since Rscript is non-interactive),
# parses the SGR codes back into (text, color) runs, and lays them out on a
# white canvas: tree connectors (rails/branches/corners) are drawn as real
# SVG <line> strokes -- continuous vector lines -- rather than stacking the
# box-drawing glyphs row by row as text, which left them looking like
# separate dashes instead of one connected line. Status glyphs and message
# text stay as monospace <text>/<tspan>, not <foreignObject>, since
# <img>-embedded SVGs generally don't render foreignObject content.

withr::local_options(cli.num_colors = 256)

ingest <- function() {
  log_step("Ingest")                     # auto step: closes when ingest() returns
  rows <- c(prices = 24318, stocks = 8790, fx = 512)
  for (name in names(rows)) {
    log_open(name, group_by = c(sources = "feed"))
    log_info(sprintf("%s rows pulled", format(rows[[name]], big.mark = ",")))
    log_close()   # close this item; the next one joins the same group
  }
}

connect <- function() {
  log_step("Connect primary")
  log_error("primary db unreachable (timeout after 5s)")  # RECOVERED: logged, keep going
  log_info("failing over to replica db-2")
  log_success("connected to replica, 12ms latency")
  log_close(status = "success")          # override: recovered, so glyph reads success
}


logtree_reset()

local({
  t <- 0
  i <- 0L
  gaps <- c(4.2, 58, 12.5, 143, 9.1, 271, 21, 87)  # seconds per now() tick
  assignInNamespace("now", function() {
    i <<- i + 1L
    t <<- t + gaps[[(i - 1L) %% length(gaps) + 1L]]
    t
  }, ns = "logtree")
})



ansi_lines <- capture.output(with_logging({
  run <- log_open("ETL run")           # manual root (block level)

  ingest()                             # auto step + grouped sub-tree
  connect()                            # auto step + recovered error

  # Manual deep branch: explicit parent links + hand-controlled batches.
  load <- log_open("Load", parent = run)  # sibling of ingest/connect, under run
  log_open("Table: facts")                # under Load (cascade-closed via load)
  log_info("opened connection pool (5 conns)")
  log_open("Batch 1/2", group_by = c(Batches = "load"))   # collapse under < Batches >
  log_info("upserted rows 1-500 of 900")
  log_close()                             # close item; next batch joins the group
  log_open("Batch 2/2", group_by = c(Batches = "load"))
  log_info("upserted rows 501-900 of 900")
  log_close()
  log_close(load)                         # cascade: Batches group + Table + Load

  log_close(run)                          # close the manual root
}))

# --- ANSI -> SVG -------------------------------------------------------

# Fixed palette cli actually emits for these SGR codes (see
# cli::ansi_html_style()), remapped to GitHub's light-theme accents so they
# read on a white background.
palette <- c(
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

parsed <- lapply(ansi_lines, parse_ansi_line)
plain  <- vapply(ansi_lines, strip_ansi, character(1))

# --- split each line into (rail/branch/corner prefix) + (glyph/text content) --

# Every prefix unit -- rail_unit() and connector_str() alike -- is exactly
# 3 characters wide ("│  ", "├─ ", "└─ "), so the
# prefix is always a whole multiple of 3 chars. Status glyphs (step/info/
# success/warning/error/group) are never box-drawing or space characters,
# so the prefix simply ends at the first character outside that set.
box_chars <- c("│", "├", "─", "└", " ")
prefix_len <- function(line) {
  chars <- strsplit(line, "")[[1]]
  n <- 0L
  for (ch in chars) {
    if (!(ch %in% box_chars)) break
    n <- n + 1L
  }
  n
}
prefix_lens <- vapply(plain, prefix_len, integer(1))

# Slice each line's colored segments at its prefix boundary; content_segs
# keeps only what's rendered as text (the prefix itself becomes vector
# lines below, computed straight from the plain characters, not segments).
content_segs <- vector("list", length(parsed))
for (i in seq_along(parsed)) {
  plen <- prefix_lens[[i]]
  pos <- 0L
  kept <- list()
  for (seg in parsed[[i]]) {
    seg_len <- nchar(seg$text)
    seg_start <- pos
    seg_end <- pos + seg_len
    if (seg_end > plen) {
      txt <- if (seg_start >= plen) seg$text else substr(seg$text, plen - seg_start + 1L, seg_len)
      kept[[length(kept) + 1L]] <- list(text = txt, color = seg$color)
    }
    pos <- seg_end
  }
  content_segs[[i]] <- kept
}

font_size   <- 13
line_height <- 19
char_width  <- 7.85
pad_x       <- 20
pad_top     <- 16
pad_bottom  <- 16

max_chars <- max(nchar(plain, type = "chars"))
width  <- ceiling(pad_x * 2 + max_chars * char_width)
height <- ceiling(pad_top + length(ansi_lines) * line_height + pad_bottom - (line_height - font_size))

row_top <- function(i) pad_top + (i - 1L) * line_height
row_mid <- function(i) row_top(i) + line_height / 2
row_bot <- function(i) row_top(i) + line_height
col_center <- function(u) pad_x + u * 3 * char_width + char_width / 2
# Stops after the dash char (unit's 2nd char), leaving its 3rd (space)
# char as a gap before the glyph -- same gap the plain-text tree has.
stub_end   <- function(u) pad_x + u * 3 * char_width + 2 * char_width

# Walk the prefix of every line unit-by-unit (each unit = 3 chars: pipe
# "│  ", branch "├─ ", or corner "└─ "). A pipe or
# branch keeps a column's vertical run open (a branch also gets a
# horizontal stub to the right); a corner closes the run at half the row's
# height -- it turns right instead of continuing down.
active   <- list()
v_segs   <- list()
h_segs   <- list()
for (i in seq_along(plain)) {
  nunits <- prefix_lens[[i]] %/% 3L
  if (nunits > 0L) {
    for (u in 0:(nunits - 1L)) {
      cell <- substr(plain[[i]], u * 3L + 1L, u * 3L + 3L)
      fc <- substr(cell, 1L, 1L)
      key <- as.character(u)
      if (fc == "└") {
        start <- if (!is.null(active[[key]])) active[[key]] else i
        v_segs[[length(v_segs) + 1L]] <- list(unit = u, start = start, end = i, half = TRUE)
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
  v_segs[[length(v_segs) + 1L]] <- list(unit = as.integer(key), start = active[[key]],
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

text_svg <- character(length(plain))
for (i in seq_along(content_segs)) {
  y <- pad_top + (i - 1L) * line_height + font_size
  x <- pad_x + prefix_lens[[i]] * char_width
  tspans <- vapply(content_segs[[i]], function(s) {
    sprintf('<tspan fill="%s">%s</tspan>', s$color, esc_xml(s$text))
  }, character(1))
  text_svg[i] <- sprintf('<text x="%.2f" y="%s" xml:space="preserve">%s</text>',
                         x, y, paste(tspans, collapse = ""))
}

svg <- paste0(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ', width, ' ', height,
  '" width="', width, '" height="', height,
  '" role="img" aria-label="Colorized logtree console output">\n',
  '<title>logtree console output</title>\n',
  '<rect x="0.5" y="0.5" width="', width - 1, '" height="', height - 1,
  '" rx="8" fill="', bg_color, '" stroke="', border_color, '"/>\n',
  '<g stroke-linecap="round">\n', paste(vline_svg, collapse = "\n"), "\n",
  paste(hline_svg, collapse = "\n"), '\n</g>\n',
  '<g font-family="ui-monospace, SFMono-Regular, &quot;SF Mono&quot;, Menlo, Consolas, monospace" font-size="', font_size, '">\n',
  paste(text_svg, collapse = "\n"), '\n',
  '</g>\n</svg>\n'
)

out_path <- "man/figures/README-tree-color.svg"
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
writeLines(svg, out_path)
cat("wrote", out_path, "(", width, "x", height, ")\n")
