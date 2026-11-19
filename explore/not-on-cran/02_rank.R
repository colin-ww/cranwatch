# 2. Rank non-CRAN packages three ways: r-universe score (one row per repo family),
# "scripts" (GitHub code that loads the package), and GitHub stars (run gh_top.sh first).
source("explore/not-on-cran/helpers.R")
all <- ru_flags()
off <- all |> filter(cran != "cran", !bioc, universe != "bioc")
cols <- c("package", "universe", "score", "dependents", "scripts", "stars", "cran", "cran_last", "multiverse", "conda_forge", "bioconda", "title")

# Same universe + same star count = (almost always) one GitHub repo, e.g. PEcAn's ~40 packages
fam <- off |>
  arrange(desc(score)) |>
  mutate(family_n = n(), .by = c(universe, stars)) |>
  distinct(universe, stars, .keep_all = TRUE)

cat("\n== by r-universe score, one per repo family ==\n")
fam |> select(all_of(cols), family_n) |> show(40)
cat("\n== by scripts (short generic names like 'debug' or 'dir' are false matches) ==\n")
fam |> arrange(desc(scripts)) |> select(all_of(cols)) |> show(25)
write_csv(fam, file.path(out, "not_on_cran_families.csv"))

# GitHub top-1000 R repos by stars, matched on repo name (approximate: r-polars -> polars)
gh_file <- file.path(out, "gh_top_r.tsv")
if (!file.exists(gh_file)) stop("run explore/not-on-cran/gh_top.sh first")
official <- tolower(c(cran_now(), bioc_pkgs()))
ru_lc    <- all |> mutate(lc = tolower(package)) |> distinct(lc, .keep_all = TRUE) |> select(lc, package, cran, universe, conda_forge)
gh <- read_tsv(gh_file, col_names = c("repo", "name", "gh_stars", "archived", "pushed", "desc"), show_col_types = FALSE, quote = "") |>
  mutate(lc = tolower(name) |> str_remove("^r-|-r$|\\.r$")) |>
  left_join(ru_lc, by = "lc") |>
  mutate(status = case_when(lc %in% official ~ "cran/bioc",
                            !is.na(package) ~ paste0("r-universe (cran: ", cran, ")"),
                            .default = "? (not a package, or GitHub-only)"))
cat("\n== GitHub top-1000 R repos ==\n"); print(count(gh, status))
cat("\nOn r-universe, not CRAN/Bioc:\n")
gh |> filter(str_starts(status, "r-universe")) |> select(repo, gh_stars, pushed, status, conda_forge, desc) |> show(30, 50)
cat("\nUnmatched, by stars (eyeball: many are books/courses; the packages are GitHub-only):\n")
gh |> filter(str_starts(status, "\\?")) |> select(repo, gh_stars, pushed, desc) |> show(60, 60)
write_csv(gh, file.path(out, "gh_top_r_flagged.csv"))
