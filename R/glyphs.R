# Non-ASCII glyphs are written as \u/\U escapes only (never literal bytes),
# per CRAN's source-portability rule for package R code. Names below refer
# to Unicode character names, not literal symbols.
#
# U+2714 = CHECK MARK                  U+2716 = HEAVY MULTIPLICATION X
# U+26A0 = WARNING SIGN                U+2139 = INFORMATION SOURCE
# U+25B6 = BLACK RIGHT-POINTING TRIANGLE
# U+25CC = DOTTED CIRCLE (used here for the "interrupted" status)
# U+251C = BOX DRAWINGS LIGHT VERTICAL AND RIGHT (tree branch)
# U+2500 = BOX DRAWINGS LIGHT HORIZONTAL
# U+2502 = BOX DRAWINGS LIGHT VERTICAL (rail)
# U+2514 = BOX DRAWINGS LIGHT UP AND RIGHT (tree corner)
# U+2699 = GEAR (unicode debug glyph)
# U+203A = SINGLE RIGHT-POINTING ANGLE QUOTATION MARK (breadcrumb separator)
#
# Beyond the glyph slots, each preset carries three non-glyph slots: `elapsed`
# (how a close line's time column is gated and styled), plus `crumb`
# (breadcrumb separator + the styling that sets the path apart from the
# message) and `summary` (the digest's divider layout), both used only by
# logtree_summary(). They live in the theme so there is one place to customise
# appearance -- logtree_theme() -- rather than a second, options-based channel.
#
# The `done` slot also carries `text`, the word a close line prints before its
# elapsed time. It is read per status (falling back to `done`'s, then to
# "Done"), so a preset -- or a user -- can rename or drop it.

glyphs_unicode <- list(
  step        = list(glyph = "\u25b6", width = 1L, color = "cyan"),
  info        = list(glyph = "\u2139", width = 1L, color = "blue"),
  debug       = list(glyph = "\u2699", width = 1L, color = "silver"),
  success     = list(glyph = "\u2714", width = 1L, color = "green"),
  # Same tick as `success` by default, but its own slot: the close ("Done")
  # line reads from `done`, so the completion tick can be restyled without
  # touching log_success() leaves (and vice versa). `text` is the word that
  # line prints before its elapsed time.
  done        = list(glyph = "\u2714", width = 1L, color = "green", text = "Done"),
  warning     = list(glyph = "\u26a0", width = 1L, color = "yellow"),
  error       = list(glyph = "\u2716", width = 1L, color = "red"),
  interrupted = list(glyph = "\u25cc", width = 1L, color = "dim"),
  group       = list(glyph = "\u25a3", color = "magenta", bracket = FALSE),
  branch      = list(glyph = "\u251c\u2500", color = "dim"),
  corner      = list(glyph = "\u2514\u2500", color = "dim"),
  pipe        = list(glyph = "\u2502", color = "dim"),
  elapsed     = list(show = TRUE, min = 0, color = NULL, slow = NULL, slow_color = "yellow"),
  crumb       = list(glyph = " \u203a ", color = "dim", path_color = "bold"),
  summary     = list(gap = 1L, rule = TRUE, line = 1L)
)

glyphs_ascii <- list(
  step        = list(glyph = ">", width = 1L, color = NULL),
  info        = list(glyph = "i", width = 1L, color = NULL),
  debug       = list(glyph = "d", width = 1L, color = NULL),
  success     = list(glyph = "+", width = 1L, color = NULL),
  done        = list(glyph = "+", width = 1L, color = NULL, text = "Done"),
  warning     = list(glyph = "!", width = 1L, color = NULL),
  error       = list(glyph = "x", width = 1L, color = NULL),
  interrupted = list(glyph = "-", width = 1L, color = NULL),
  group       = list(glyph = "", color = NULL, bracket = TRUE),
  # Same connector for branch and corner: ASCII has no distinct corner
  # glyph, the closing line's own status glyph + elapsed time mark the end
  # of a group instead (see design doc section 4.1).
  branch      = list(glyph = "|-", color = NULL),
  corner      = list(glyph = "|-", color = NULL),
  pipe        = list(glyph = "|", color = NULL),
  # No `slow_color` either: this preset is colorless by design, so a slow time
  # is left to the reader rather than highlighted.
  elapsed     = list(show = TRUE, min = 0, color = NULL, slow = NULL, slow_color = NULL),
  # Plain ASCII throughout, colorless like every other slot of this preset --
  # which is what makes ascii output stable and easy to pattern-match in tests.
  crumb       = list(glyph = " > ", color = NULL, path_color = NULL),
  summary     = list(gap = 1L, rule = TRUE, line = "-")
)

# U+1F539 = SMALL BLUE DIAMOND        U+1F4A1 = ELECTRIC LIGHT BULB
# U+2705  = WHITE HEAVY CHECK MARK    U+274C  = CROSS MARK
# U+2753  = BLACK QUESTION MARK ORNAMENT
# U+26A0 U+FE0F = WARNING SIGN + VARIATION SELECTOR-16 (emoji presentation)
# U+1F41B = BUG (emoji debug glyph)

glyphs_emoji <- list(
  step        = list(glyph = "\U0001f539", width = 2L, color = NULL),
  info        = list(glyph = "\U0001f4a1", width = 2L, color = NULL),
  debug       = list(glyph = "\U0001f41b", width = 2L, color = NULL),
  success     = list(glyph = "\u2705", width = 2L, color = NULL),
  done        = list(glyph = "\u2705", width = 2L, color = NULL, text = "Done"),
  warning     = list(glyph = "\u26a0\ufe0f", width = 2L, color = NULL),
  error       = list(glyph = "\u274c", width = 2L, color = NULL),
  interrupted = list(glyph = "\u2753", width = 2L, color = NULL),
  group       = list(glyph = "\u25a3", color = "magenta", bracket = FALSE),
  # Tree connectors stay box-drawing even under the emoji preset.
  branch      = list(glyph = "\u251c\u2500", color = "dim"),
  corner      = list(glyph = "\u2514\u2500", color = "dim"),
  pipe        = list(glyph = "\u2502", color = "dim"),
  elapsed     = list(show = TRUE, min = 0, color = NULL, slow = NULL, slow_color = "yellow"),
  crumb       = list(glyph = " \u203a ", color = "dim", path_color = "bold"),
  summary     = list(gap = 1L, rule = TRUE, line = 1L)
)
