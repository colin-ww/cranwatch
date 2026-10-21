# Knobs -----------------------------------------------------------------------

# owner/name of this repo (set by GitHub Actions), so forks identify as themselves
gh_repo <- Sys.getenv("GITHUB_REPOSITORY", "colin-ww/cranwatch")

settings <- list(
  # Who we are, on every request (r-universe docs + GitHub API ask for a UA)
  user_agent        = paste0("cranwatch/0.1 (+https://github.com/", gh_repo, ")"),
  site_url          = paste0("https://", dirname(gh_repo), ".github.io/", basename(gh_repo), "/"),
  # Politeness: every GET is cached on disk and reused for this long, and
  # requests to one host are spaced at least 1 / max_req_per_sec seconds apart
  cache_dir         = "_cache",
  cache_hours       = 20,
  max_req_per_sec   = 2,
  # Sources
  cran_base         = "https://cloud.r-project.org", # CRAN's CDN mirror, spares the Vienna master
  ru_global         = "https://r-universe.dev",      # global search: every indexed package
  ru_universe       = "https://{universe}.r-universe.dev",
  ru_page_size      = 5000, # bigger pages hit MongoDB's 16 MB document cap server-side
  cranlogs_base     = "https://cranlogs.r-pkg.org",
  github_api        = "https://api.github.com",
  dl_lag_days       = 2,  # cranlogs lags ~1 day; 2 is safe
  dl_chunk          = 50, # packages per cranlogs request
  revdep_min_score  = 10, # "notable" reverse dependency = r-universe score above this
  revdep_min_n      = 3,  # ...and only list the top ones if at least this many
  revdep_top_n      = 3,
  strong_deps       = c("Depends", "Imports", "LinkingTo"),
  # The 9 packages library(tidyverse) attaches; install.packages("tidyverse") also
  # brings the rest of its Imports. Deps are counted beyond that baseline.
  tidyverse_core    = c("ggplot2", "dplyr", "tidyr", "readr", "purrr", "tibble", "stringr", "forcats", "lubridate"),
  ru_multiverse     = "https://r-multiverse.r-universe.dev", # R-multiverse's curated universe
  not_on_cran_n     = 25,
  not_on_cran_skip  = c("cran", "bioc"), # universes left out of the "top scoring, not on CRAN" list

  # SystemRequirements items not worth *showing* (watch flags still see them):
  # compilers/make, and split-off continuations ("or ...", "see the README", "and ...")
  sysreq_noise      = "(?i)^(gnu make|c\\+\\+\\s*\\d*)$|^(or|see|for|and)\\b",
  # What goes in the alert issue: CRAN-side risks, announced once each. not-found /
  # gh-archived are watchlist housekeeping: flags + a to-do list on the site, no email.
  alert_types       = c("deadline", "archived", "orphaned"),
  alert_archived_days = 90 # an archival older than this is history: on the site, not in the issue
)
