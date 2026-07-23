usethis::use_release_issue()


usethis::use_news_md()        # changelog
usethis::use_cran_comments()  # notes to CRAN reviewers


devtools::check_win_devel()    # Windows + R-devel (required by policy)
devtools::check_mac_release()  # CRAN's macOS builder
rhub::rhub_check()              # multi-platform via R-hub (rhub v2)
