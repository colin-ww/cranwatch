# Source the pipeline + build fake sources so tests run offline ----------------

for (f in list.files(test_path("../../R"), pattern = "\\.R$", full.names = TRUE)) source(f)

test_today <- as.Date("2026-10-08")

fake_db <- tribble(
  ~Package, ~Version, ~Title, ~Published, ~Deadline, ~NeedsCompilation, ~SystemRequirements, ~URL, ~`X-CRAN-Comment`, ~`X-CRAN-History`, ~Depends, ~Imports, ~LinkingTo, ~Maintainer, ~Author,
  "alpha", "1.0", "Alpha", "2026-01-01", NA, "no", NA, "https://github.com/me/alpha", NA, "Archived on 2026-03-01 as issues.\nUnarchived on 2026-04-01.", "R (>= 4.1)", "beta, stats", NA, "Hadley Wickham <h@example.org>", "Hadley Wickham [aut, cre], Posit Software, PBC [cph, fnd]",
  "beta", "2.0", "Beta", "2025-06-01", NA, "yes", "libxml2 (optional), glpk (>= 4.57, optional), GNU make", NA, NA, NA, NA, "Rcpp", "Rcpp", "Bea Person <b@example.org>", "Bea Person [aut, cre]",
  "Rcpp", "1.1", "Rcpp", "2025-01-01", NA, "yes", NA, NA, NA, NA, NA, "methods", NA, "Rae Person <r@example.org>", "Rae Person [aut, cre], Hadley Wickham [ctb]",
  "delta", "0.1", "Delta", "2024-01-01", "2026-10-20", "no", "cmake", NA, NA, NA, NA, NA, NA, "Dee Person <d@example.org>", "Dee Person [aut, cre]",
  "kilo", "1.0", "Kilo", "2024-01-01", NA, "no", NA, NA, NA, NA, NA, NA, NA, "ORPHANED", "Someone Gone [aut]",
  "rev1", "1", "r1", "2025-01-01", NA, "no", NA, NA, NA, NA, NA, "alpha", NA, "Someone <s@example.org>", NA,
  "rev2", "1", "r2", "2025-01-01", NA, "no", NA, NA, NA, NA, "alpha", NA, NA, "Someone <s@example.org>", NA,
  "rev3", "1", "r3", "2025-01-01", NA, "no", NA, NA, NA, NA, NA, "alpha", NA, "Someone <s@example.org>", NA,
  "rev4", "1", "r4", "2025-01-01", NA, "no", NA, NA, NA, NA, NA, "alpha", NA, "Someone <s@example.org>", NA,
  # stand-in for the tidyverse meta-package: install.packages("tidyverse") brings Rcpp
  "tidyverse", "2.0", "Tidyverse", "2025-01-01", NA, "no", NA, NA, NA, NA, NA, "Rcpp", NA, "Someone <s@example.org>", NA
)

fake_cran_in <- tibble(
  package = c("alpha", "echo"),
  comment = c(NA, "Archived on 2026-09-01 as check problems were not corrected in time."),
  history = NA_character_
)

# r-universe global index (search) + per-universe detail (score ingredients)
fake_index <- tribble(
  ~package, ~universe, ~score, ~stars, ~dependents, ~scripts,
  "alpha", "me", 12, 40, 4, 0,
  "alpha", "fork", 3, 0, 0, 0,
  "beta", "cran", 8, 2, 1, 0,
  "rev1", "cran", 15, 1, 0, 0,
  "rev2", "cran", 20, 1, 0, 0,
  "rev3", "cran", 11, 1, 0, 0,
  "rev4", "cran", 5, 1, 0, 0,
  "foxtrot", "someone", 4, 9, 0, 0
)

fake_detail <- \(picked) {
  tibble(package = "alpha", universe = "me", score = 12, stars = 40, dependents = 4, scripts = 0,
         downloads = 900, update_weeks = 6, commits = 30, contributors = 3, on_cran = TRUE, readme = TRUE) |>
    semi_join(picked, by = c("package", "universe"))
}

fake_fetchers <- function(...) {
  list(
    cran_db    = \() add_na_cols(fake_db, cran_fields),
    cran_in    = \() fake_cran_in,
    ru_index   = \() fake_index,
    ru_detail  = fake_detail,
    ru_sysdeps = \() tibble(library = c("libxml2", "glpk"), package = "beta"),
    downloads  = \(pkgs, today) tibble(package = pkgs, dl_365 = 100, dl_prev365 = if_else(pkgs == "delta", 0, 50)) |>
      mutate(dl_growth = if_else(dl_prev365 > 0, dl_365 / dl_prev365 - 1, NA_real_)),
    github     = \(repos) tibble(repo = "own/golf", gh_stars = 3, gh_pushed = test_today, gh_archived = FALSE, gh_is_pkg = TRUE) |>
      filter(repo %in% repos)
  ) |>
    list_modify(...)
}

# Temp repo root with a small watchlist
fake_root <- function() {
  root <- tempfile("cranwatch-")
  dir.create(root)
  writeLines(c(
    "core:", "  - alpha", "  - beta", "  - delta",
    "other:", "  - alpha", "  - echo", "  - foxtrot", "  - kilo", "  - Rcpp", "  - own/golf", "  - own/hotel", "  - stats4"
  ), file.path(root, "packages.yml"))
  writeLines(c("compile-only:", "  - cmake", "run:", "  - libxml2"), file.path(root, "sys-deps.yml"))
  root
}
