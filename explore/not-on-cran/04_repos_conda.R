# 4. Other CRAN-like repos (R-Forge & co), Bioc vs CRAN overlap, and what's in the conda channels:
# Anaconda's old `r` channel vs conda-forge, and conda-forge's r-* that aren't on CRAN.
source("explore/not-on-cran/helpers.R")
all  <- ru_flags()
now  <- cran_now()
ever <- cran_ever()
bioc <- bioc_pkgs()

cat("== other CRAN-like repos ==\n")
c(`R-Forge`    = "https://R-Forge.R-project.org/src/contrib/PACKAGES",
  `RForge.net` = "https://www.rforge.net/src/contrib/PACKAGES",
  Omegahat     = "https://www.omegahat.net/R/src/contrib/PACKAGES",
  Stan         = "https://mc-stan.org/r-packages/src/contrib/PACKAGES",
  INLA         = "https://inla.r-inla-download.org/R/stable/src/contrib/PACKAGES") |>
  imap(\(u, repo) {
    p <- dcf_pkgs(u)
    tibble(repo, packages = length(p), not_cran_bioc = sum(!p %in% c(now, bioc)), never_cran = sum(!p %in% c(ever, bioc)))
  }) |>
  list_rbind() |> print()

cat("\n== Bioc vs CRAN ==\n")
cat("Bioc release names also on CRAN now:", sum(bioc %in% now), "| once on CRAN:", sum(bioc %in% ever), "\n")

# conda: r-* names, last build year, and whether they're CRAN packages
conda_r <- \(ch) conda_channel(ch) |>
  imap(\(x, name) tibble(name, version = x$version %||% NA, ts = as.numeric(x$timestamp %||% NA))) |>
  list_rbind() |>
  filter(str_starts(name, "r-")) |>
  mutate(year = year(as_datetime(if_else(ts > 1e11, ts / 1000, ts))),
         lc   = str_remove(name, "^r-"),
         class = case_when(lc %in% tolower(now)         ~ "current CRAN",
                           lc %in% tolower(ever)        ~ "archived from CRAN",
                           lc %in% tolower(bioc)        ~ "Bioconductor",
                           lc %in% tolower(all$package) ~ "r-universe only",
                           .default = "other (r-base, tools, GitHub-only, renamed)"))
r_ch <- conda_r("r") # Anaconda's channel; part of "defaults"
cf   <- conda_r("conda-forge")

cat("\n== conda r-* by class ==\n")
bind_rows(r = r_ch, `conda-forge` = cf, .id = "channel") |>
  count(channel, class) |> pivot_wider(names_from = channel, values_from = n) |> print()
cat("\nr-base latest: r channel", r_ch$version[r_ch$name == "r-base"], "| conda-forge", cf$version[cf$name == "r-base"], "\n")
cat("Names on both:", length(intersect(r_ch$name, cf$name)), "\n")
cat("\nLast build year, r channel:\n");                       print(count(r_ch, year))
cat("\nLast build year, conda-forge r-* archived from CRAN:\n"); print(count(filter(cf, class == "archived from CRAN"), year))
cat("\nconda-forge r-* not on current CRAN, examples:\n")
cf |> filter(class != "current CRAN") |>
  summarise(n = n(), examples = paste(head(lc, 15), collapse = " "), .by = class) |> show(10, 200)
write_csv(cf, file.path(out, "conda_forge_r.csv"))
