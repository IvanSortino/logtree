# compact = "medium" renders with a tighter tree column (ascii)

    Code
      compact_fixture()
    Output
      > Pipeline
      |-> Load config
      | |-i Reading config.yml
      | |-+ Done  0.03s
      |-+ Done  0.15s

# compact = "tight" renders with single-column indentation (ascii)

    Code
      compact_fixture()
    Output
      > Pipeline
      |> Load config
      ||i Reading config.yml
      ||+ Done  0.03s
      |+ Done  0.15s

