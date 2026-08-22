# min = 0.1 silences the fast steps of a whole tree (ascii)

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
      |- > Load config
      |  |- i Reading config.yml
      |  |- + Done
      |- + Done  0.15s

