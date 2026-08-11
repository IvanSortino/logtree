# connector_gap renders a whole tree (ascii)

    Code
      logtree_reset()
      pipeline <- (function() {
        log_step("Pipeline")
        load_config()
      })
      load_config <- (function() {
        log_step("Load config")
        log_info("Reading config.yml")
      })
      pipeline()
    Output
      > Pipeline
      |> Load config
      || i Reading config.yml
      || + Done  0.03s
      | + Done  0.15s

