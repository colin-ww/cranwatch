# Shared helpers for the explore/not-on-cran scripts. Run every script from the repo root:
#   Rscript explore/not-on-cran/01_index.R
# Not part of the cranwatch workflow: nothing in R/ or run.R uses this folder.
suppressMessages(library(tidyverse))

here  <- "explore/not-on-cran"
cache <- file.path(here, "_cache") # gitignored
out   <- file.path(here, "out")
walk(c(cache, out), \(d) dir.create(d, showWarnings = FALSE))

# GET once, reuse for a day. Same politeness idea as cranwatch's cached_get(), minus the counters.
get <- function(url, hours = 24) {
  url  <- as.character(url) # glue strings hash differently
  path <- file.path(cache, rlang::hash(url))
  if (!file.exists(path) || difftime(Sys.time(), file.mtime(path), units = "hours") > hours) {
    Sys.sleep(0.5)
    httr2::request(url) |>
      httr2::req_user_agent("r-pkg-landscape-explorer/0.1") |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_timeout(300) |>
      httr2::req_perform(path = path)
  }
  path
}
read_json <- \(url, ...) jsonlite::fromJSON(get(url), ...)
dcf_pkgs  <- \(url) tryCatch(unique(read.dcf(get(url), fields = "Package")[, 1]), error = \(e) character())
deps_of   <- \(x) x |> str_remove_all("\\([^)]*\\)") |> str_split(",") |> unlist() |> str_squish() |> discard(\(d) d %in% c("", "R"))

# CRAN: current db, archive (= every package that ever had an older version), archive reasons
cran_db      <- \() readRDS(get("https://cloud.r-project.org/web/packages/packages.rds")) |> as_tibble()
cran_archive <- \() readRDS(get("https://cloud.r-project.org/src/contrib/Meta/archive.rds"))
cran_now     <- \() unique(cran_db()$Package)
cran_ever    <- \() union(cran_now(), names(cran_archive()))
cran_reasons <- \() read.dcf(get("https://cloud.r-project.org/src/contrib/PACKAGES.in"), all = TRUE) |>
  as_tibble() |>
  select(package = Package, any_of(c(cran_comment = "X-CRAN-Comment"))) |>
  mutate(cran_comment = str_squish(cran_comment))
base_pkgs <- rownames(installed.packages(priority = "base"))

bioc_repos <- c("bioc", "data/annotation", "data/experiment", "workflows", "books")
bioc_pkgs  <- \(repos = bioc_repos) repos |>
  map(\(r) dcf_pkgs(glue::glue("https://bioconductor.org/packages/release/{r}/src/contrib/PACKAGES"))) |>
  unlist() |> unique()

# conda: every package name on a channel (conda-forge ~24 MB, bioconda ~12 MB)
conda_channel <- \(ch) read_json(glue::glue("https://conda.anaconda.org/{ch}/channeldata.json"), simplifyVector = FALSE)$packages
conda_names   <- \(ch) names(conda_channel(ch))
to_conda      <- \(pkg) paste0("r-", tolower(pkg)) # R package -> conda-forge name (Bioc: "bioconductor-")

# Written by 01_index.R, read by the others
ru_flags <- \() read_csv(file.path(out, "ru_all_flags.csv"), show_col_types = FALSE)

show <- \(df, n = 40, width = 45) df |>
  mutate(across(any_of(c("title", "desc", "cran_comment")), \(x) str_trunc(x, width))) |>
  head(n) |> as.data.frame() |> print(right = FALSE)
