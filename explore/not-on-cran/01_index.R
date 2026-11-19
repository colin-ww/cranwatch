# 1. Every r-universe package, flagged: on CRAN (now / archived / never), Bioc, R-multiverse, conda.
# Bulk downloads only (~20 requests, ~50 MB). Writes out/ru_all_flags.csv, out/not_on_cran.csv, out/counts.csv
source("explore/not-on-cran/helpers.R")

# r-universe global search, no query = every indexed package ranked by score, 5000 per page
ru_page <- \(skip) read_json(glue::glue("https://r-universe.dev/api/search?limit=5000&skip={skip}"))
first   <- ru_page(0)
ru_all  <- c(list(first), map(seq(5000, first$total - 1, by = 5000), ru_page)) |>
  map(\(p) p$results |> as_tibble() |>
        select(package = Package, universe = `_user`, score = `_score`, dependents = `_usedby`,
               scripts = `_searchresults`, stars, title = Title)) |>
  list_rbind()
ru <- ru_all |> arrange(desc(score)) |> distinct(package, .keep_all = TRUE) # highest-scoring universe = home

cran_last <- cran_archive() |>
  imap(\(df, pkg) tibble(package = pkg, cran_last = as.Date(max(df$mtime)))) |>
  list_rbind()
now  <- cran_now()
bioc <- bioc_pkgs()

mv_comm <- read_json("https://community.r-multiverse.org/api/packages?fields=Package,_cranurl&limit=100000") |> as_tibble()
mv_prod <- read_lines(get("https://r-multiverse.org/production.html")) |>
  str_extract("https://production\\.r-multiverse\\.org/\\d{4}-\\d{2}-\\d{2}") |>
  discard(is.na) |> sort() |> last() |>
  paste0("/src/contrib/PACKAGES") |> dcf_pkgs()

cf <- conda_names("conda-forge")
bc <- conda_names("bioconda")

flags <- ru |>
  left_join(cran_last, by = "package") |>
  left_join(cran_reasons(), by = "package") |>
  mutate(
    cran        = case_when(package %in% now ~ "cran", !is.na(cran_last) ~ "archived", .default = "never"),
    bioc        = package %in% bioc,
    multiverse  = case_when(package %in% mv_prod ~ "production", package %in% mv_comm$Package ~ "community"),
    conda_forge = to_conda(package) %in% cf,
    bioconda    = to_conda(package) %in% bc | paste0("bioconductor-", tolower(package)) %in% bc
  )
not_cran <- flags |> filter(cran != "cran", !bioc, universe != "bioc") # bioc universe also holds Bioc devel

counts <- tribble(
  ~what,                                            ~n,
  "CRAN, current",                                  length(now),
  "CRAN, ever (incl. archived)",                    length(cran_ever()),
  "Bioconductor release, all repos",                length(bioc),
  "r-universe, /api/summary packages",              read_json("https://r-universe.dev/api/summary?all=true")$packages,
  "r-universe, unique names in search index",       nrow(ru),
  "r-universe, not on CRAN or Bioc",                nrow(not_cran),
  "r-universe, not on CRAN or Bioc, CRAN-archived", sum(not_cran$cran == "archived"),
  "R-multiverse community",                         nrow(mv_comm),
  "R-multiverse community, not on CRAN",            sum(!coalesce(as.logical(mv_comm$`_cranurl`), FALSE)),
  "R-multiverse production (latest snapshot)",      length(mv_prod),
  "conda-forge r-*",                                sum(str_starts(cf, "r-")),
  "conda-forge r-* that are current CRAN",          sum(to_conda(now) %in% cf),
  "bioconda r-* + bioconductor-*",                  sum(str_starts(bc, "r-|bioconductor-"))
)
print(counts, n = Inf)

write_csv(counts, file.path(out, "counts.csv"))
write_csv(flags, file.path(out, "ru_all_flags.csv"))
not_cran |> arrange(desc(score)) |> select(-cran_comment) |> write_csv(file.path(out, "not_on_cran.csv"))
not_cran |> arrange(desc(score)) |>
  select(package, universe, score, dependents, scripts, stars, cran, cran_last, multiverse, conda_forge, bioconda, title) |>
  show(30)
