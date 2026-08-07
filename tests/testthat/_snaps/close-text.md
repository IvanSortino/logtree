# a renamed close line renders through a whole tree (ascii)

    Code
      logtree_reset()
      pipeline <- (function() {
        log_step("Pipeline")
        load_config()
      })
      load_config <- (function() {
        log_step("Load config")
        log_error("config.yml missing")
      })
      pipeline()
    Output
      > Pipeline
      |- > Load config
      |  |- x config.yml missing
      |  |- x Load config FAILED  0.03s
      |- + Pipeline ok  0.15s

