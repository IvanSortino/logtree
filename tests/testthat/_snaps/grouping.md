# grouped tree renders as expected (ascii snapshot)

    Code
      cat(capture.output(with_logging(run(), summary = FALSE)), sep = "\n")
    Output
      > Pipeline
      |- < Item 1 >
      |  |- > validate
      |  |  |- i validate running
      |  |  |- + Done  0.00s
      |  |- > bounds
      |  |  |- i bounds running
      |  |  |- + Done  0.00s
      |  |- + Done  0.00s
      |- < Item 2 >
      |  |- > validate
      |  |  |- i validate running
      |  |  |- + Done  0.00s
      |  |- > bounds
      |  |  |- i bounds running
      |  |  |- + Done  0.00s
      |  |- + Done  0.00s
      |- + done
      |- + Done  0.00s

