# glyph_gap = 2 renders a roomier tree (ascii)

    Code
      gap_fixture()
    Output
      >  Pipeline
      |- >  Load config
      |  |- i  Reading config.yml
      |  |- +  Done  0.03s
      |- +  Done  0.15s

# glyph_gap composes with compact = "tight" (ascii)

    Code
      gap_fixture()
    Output
      >Pipeline
      |>Load config
      ||iReading config.yml
      ||+Done  0.03s
      |+Done  0.15s

