# Snapshot schema -------------------------------------------------------------
# The single place that defines snapshot columns (order + type). Every source
# fills in what it can; conform() adds the rest as NA, so the CSV keeps the same
# shape even when an API is down, and old snapshots read fine after new
# columns are added.

snapshot_cols <- c(
  run_date          = "date",
  package           = "chr",
  themes            = "chr",
  status            = "chr", # base / cran / cran-archived / r-universe / github / not-found / unknown
  lookups_ok        = "lgl", # FALSE: a lookup source failed this run (some statuses "unknown", alerts partial)
  title             = "chr",
  version           = "chr",
  published         = "date",
  link              = "chr",
  repo              = "chr",
  # people + curation
  maintainer        = "chr", # CRAN maintainer's name (no email)
  hadley            = "chr", # maintainer / author (CRAN) or contributor (GitHub commits, via r-universe) if Hadley Wickham
  funders           = "chr", # authors with the "fnd" role, e.g. Posit Software, PBC
  multiverse        = "lgl", # in R-multiverse
  ru_universes      = "chr", # r-universe universes hosting a package of this name, besides the cran mirror
  ru_universes_n    = "dbl",
  # popularity: r-universe score + the ingredients it's computed from
  ru_universe       = "chr",
  ru_score          = "dbl",
  ru_stars          = "dbl",
  ru_dependents     = "dbl", # recursive, across all of r-universe
  ru_scripts        = "dbl", # GitHub scripts that load it
  ru_downloads      = "dbl", # last month, cranlogs
  ru_mentions       = "dbl",
  ru_update_weeks   = "dbl", # weeks with commits, past year
  ru_commits        = "dbl",
  ru_contributors   = "dbl",
  ru_vignettes      = "dbl",
  ru_datasets       = "dbl",
  ru_releases       = "dbl",
  ru_on_cran        = "lgl",
  ru_readme         = "lgl",
  # downloads: cranlogs (Posit CRAN mirror only)
  dl_365            = "dbl",
  dl_prev365        = "dbl",
  dl_growth         = "dbl",
  # CRAN health
  deadline          = "date",
  archived_n        = "dbl",
  archived_last     = "date",
  cran_comment      = "chr",
  orphaned          = "lgl",
  # install burden
  needs_compilation = "lgl",
  deps_n            = "dbl",
  deps_extra_n      = "dbl", # recursive deps beyond what install.packages("tidyverse") brings
  tidyverse         = "chr", # core / member / dep: part of a tidyverse install, NA = not
  deps              = "chr", # the recursive deps themselves, "; "-separated (CSV only)
  sysreqs           = "chr",
  sysreqs_via_deps  = "chr",
  sysdeps_detected  = "chr",
  sysreqs_watch     = "chr",
  # reverse dependencies
  revdeps_n         = "dbl",
  revdeps_notable_n = "dbl",
  revdeps_top       = "chr",
  # GitHub: only looked up for packages not found on CRAN / r-universe
  gh_stars          = "dbl",
  gh_pushed         = "date",
  gh_archived       = "lgl",
  gh_is_pkg         = "lgl",
  flags             = "chr"
)

na_of_type <- list(chr = NA_character_, dbl = NA_real_, lgl = NA, date = as.Date(NA))

# Add any missing schema columns as typed NAs (extra columns are kept)
ensure_cols <- function(df) {
  missing <- setdiff(names(snapshot_cols), names(df))
  df |> mutate(!!!set_names(na_of_type[snapshot_cols[missing]], missing))
}

conform <- function(df) df |> ensure_cols() |> select(all_of(names(snapshot_cols)))

read_snapshot <- function(path) {
  spec <- snapshot_cols |>
    map(\(type) switch(type, chr = col_character(), dbl = col_double(), lgl = col_logical(), date = col_date()))

  read_csv(path, col_types = do.call(cols_only, spec), show_col_types = FALSE, progress = FALSE) |>
    suppressWarnings() |> # older snapshots may lack newer columns
    conform()
}
