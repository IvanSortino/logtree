# leaf close = TRUE renders a corner leaf and no Done line (unicode)

    Code
      log_open("Step 2")
    Output
      ▶ Step 2
    Code
      log_warn("child warn 1", close = TRUE)
    Output
      └─ ⚠ child warn 1

