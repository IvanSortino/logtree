# unicode theme renders and aligns as expected

    Code
      render_fixture()
    Output
      ▶ Pipeline
      ├─ ▶ Load config
      │  ├─ ℹ Reading config.yml
      │  └─ ✔ Done  0.03s
      └─ ✔ Done  0.15s

# ascii theme renders and aligns as expected

    Code
      render_fixture()
    Output
      > Pipeline
      |- > Load config
      |  |- i Reading config.yml
      |  |- + Done  0.03s
      |- + Done  0.15s

# emoji theme renders and aligns as expected

    Code
      render_fixture()
    Output
      🔹 Pipeline
      ├─ 🔹 Load config
      │  ├─ 💡 Reading config.yml
      │  └─ ✅ Done  0.03s
      └─ ✅ Done  0.15s

