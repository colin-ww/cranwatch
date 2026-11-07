# r-universe: scores, score components, detected system libraries -------------
# Mostly bulk requests, not one per package (all cached, see cached_get()):
#   1. ru_index:   /api/search with no query = every package, ranked by score,
#                  in pages of 5000: the global index (~7 pages) plus the cran
#                  universe's (~6 pages) for CRAN packages global search leaves
#                  out (e.g. future, gridExtra). Gives score, recursive
#                  dependents, scripts, stars + each package's home universe.
#                  Used for revdep ranking and to find watched packages.
#   2. ru_detail:  /api/packages?fields=... once per universe that hosts a
#                  watched package (~55), + one call per watched package that
#                  listing doesn't return (~10). Gives the score's ingredients.
#   3. ru_sysdeps: /api/sysdeps on the cran universe: system library -> packages.
# NB a CRAN package's copy in the `cran` universe isn't its canonical record when
# it has a home universe (e.g. dplyr -> tidyverse: 5 vs 5000 stars), hence the
# global index first.

ru_url <- function(universe, path) paste0(glue(settings$ru_universe, universe = universe), path)

ru_index_cols <- c(
  package = "Package", universe = "_user", score = "_score",
  dependents = "_usedby", scripts = "_searchresults", stars = "stars"
)

fetch_ru_index <- function() {
  global <- ru_search_all(settings$ru_global)
  # the cran supplement is optional: if it fails, keep the global index (attr "partial")
  cran <- tryCatch(ru_search_all(ru_url("cran", "")), error = \(e) {
    msg("ru_index: cran universe search failed - {conditionMessage(e)}")
    NULL
  })
  out <- bind_rows(global, if (!is.null(cran)) anti_join(cran, global, by = "package"))
  if (is.null(cran)) attr(out, "partial") <- "cran universe search failed"
  out
}

ru_search_all <- function(base) {
  size  <- settings$ru_page_size
  page  <- \(skip) glue("{base}/api/search?limit={size}&skip={skip}") |> cached_get() |> fromJSON()
  first <- page(0)
  skips <- if (first$total > size) seq(size, first$total - 1, by = size) else numeric()

  c(list(first), map(skips, page)) |>
    map(\(p) as_tibble(p$results) |> select(any_of(ru_index_cols))) |>
    list_rbind() |>
    mutate(across(c(score, dependents, scripts, stars), as_num)) |>
    distinct(package, universe, .keep_all = TRUE) # paging by score can repeat ties at page edges
}

# Each watched package's home universe: the one matching the repo owner in
# packages.yml if any, else the highest-scoring package of that name
ru_pick <- function(index, watch) {
  watch |>
    select(package, repo) |>
    inner_join(index, by = "package", relationship = "many-to-many") |>
    mutate(owner_match = coalesce(tolower(universe) == tolower(str_extract(repo, "^[^/]+")), FALSE)) |>
    arrange(desc(owner_match), desc(score)) |>
    distinct(package, .keep_all = TRUE) |>
    select(-repo, -owner_match)
}

ru_detail_fields <- c(
  "_score", "_stars", "_usedby", "_searchresults", "_downloads", "_mentions", "_readme", "_cranurl", "_bioc",
  "_updates", "_contributors.user", "_vignettes.title", "_datasets.name", "_releases.version"
)

# A universe or package that fails is skipped (and listed in attr "failed"), not fatal
fetch_ru_detail <- function(picked) {
  none   <- tibble(package = character(), universe = character()) # typed: list_rbind(list()) has no columns
  failed <- character()
  try_or_skip <- \(what, f) tryCatch(f(), error = \(e) {
    failed <<- c(failed, what)
    msg("ru_detail: {what} failed - {conditionMessage(e)}")
    NULL
  })

  listed <- picked |>
    distinct(universe) |>
    pull() |>
    map(\(u) try_or_skip(u, \() ru_universe_detail(u, picked))) |>
    list_rbind() |>
    bind_rows(none)

  # The cran universe only lists its indexed packages: fetch the rest one by one
  single <- picked |>
    anti_join(listed, by = c("package", "universe")) |>
    filter(!universe %in% failed) |>
    select(package, universe) |>
    pmap(\(package, universe) try_or_skip(paste0(universe, "/", package), \() {
      ru_url(universe, paste0("/api/packages/", package)) |>
        cached_get() |>
        fromJSON(simplifyVector = FALSE) |>
        ru_components()
    })) |>
    list_rbind() |>
    bind_rows(none)

  out <- bind_rows(listed, single)
  attr(out, "failed") <- failed
  out
}

ru_universe_detail <- function(universe, picked) {
  rows <- ru_url(universe, "/api/packages") |>
    paste0("?stream=true&limit=10000&fields=", paste(ru_detail_fields, collapse = ",")) |>
    cached_get() |>
    readLines(warn = FALSE, encoding = "UTF-8") |>
    keep(\(line) str_extract(line, '^\\{"Package":"([^"]+)"', group = 1) %in% picked$package) |> # parse only ours
    map(\(line) ru_components(fromJSON(line, simplifyVector = FALSE))) |>
    list_rbind()

  bind_rows(tibble(package = character(), universe = character()), rows) |> semi_join(picked, by = c("package", "universe"))
}

# One package record -> the numbers r-universe's score is built from
ru_components <- function(doc) {
  n      <- \(x) length(x %||% list())
  num    <- \(x) as_num(x %||% NA)
  truthy <- \(x) !is.null(x) && !identical(x, FALSE) && !identical(x, "") # JavaScript truthiness

  tibble(
    package      = doc$Package,
    universe     = doc$`_user`,
    score        = num(doc$`_score`),
    stars        = num(doc$`_stars`),
    dependents   = num(doc$`_usedby`),
    scripts      = num(doc$`_searchresults`),
    downloads    = num(doc$`_downloads`$count),
    mentions     = num(doc$`_mentions`),
    update_weeks = n(doc$`_updates`),
    commits      = sum(map_dbl(doc$`_updates` %||% list(), \(u) num(u$n))),
    contributors = n(doc$`_contributors`),
    hadley       = "hadley" %in% map_chr(doc$`_contributors` %||% list(), \(c) c$user %||% NA_character_), # top 100 by commits
    vignettes    = n(doc$`_vignettes`),
    datasets     = n(doc$`_datasets`),
    releases     = n(doc$`_releases`),
    on_cran      = truthy(doc$`_cranurl`) || truthy(doc$`_bioc`),
    readme       = truthy(doc$`_readme`)
  )
}

# r-universe's calculate_score() (r-universe-org/frontend, routes/packages.js),
# term by term: score = 1 + rowSums(ru_score_parts(df)). Each ingredient is
# log10-scaled and weighted relative to GitHub stars ("1 revdep ~ 3 stars"),
# so 10 stars = 1 point, 100 stars = 2 points, ...
# Datasets are meant to count too, but a bug upstream means they never do.
# prefix = "ru_" for snapshot columns.
ru_score_parts <- function(df, prefix = "") {
  col <- \(x) df[[paste0(prefix, x)]]
  pts <- \(x) log10(pmax(1, coalesce(as.numeric(x), 0)))

  tibble(
    stars        = pts(col("stars")),
    dependents   = pts(col("dependents") * 3),
    scripts      = pts(col("scripts") / 10),
    vignettes    = pts(col("vignettes") * 10),
    activity     = pts(col("update_weeks")),
    contributors = pts(col("contributors") - 1),
    cran         = pts(if_else(col("on_cran") %in% TRUE, 10, 0)),
    readme       = pts(if_else(col("readme") %in% TRUE, 5, 0)),
    downloads    = pts(col("downloads") / 1000),
    mentions     = pts(pmin(col("mentions"), 10))
  )
}

# Share of packages where our recomputed score matches r-universe's: < 1 means
# they changed the formula and ru_score_parts() needs updating
ru_formula_match <- function(detail) {
  if (!nrow(detail)) return(NA_real_)
  mean(abs(1 + rowSums(ru_score_parts(detail)) - detail$score) < 0.01, na.rm = TRUE)
}

# One row per watched package found on r-universe: ingredients from ru_detail
# where we have them, else the headline numbers from the index; plus every
# universe that hosts a package of that name (the cran mirror aside)
ru_metrics <- function(index, detail, watch) {
  if (is.null(index)) return(tibble(package = character(), ru_universe = character()))
  picked <- ru_pick(index, watch)
  detail <- detail %||% tibble(package = character(), universe = character())

  hosts <- index |>
    filter(!universe %in% "cran", package %in% picked$package) |>
    summarise(ru_universes = paste(sort(unique(universe)), collapse = "; "), ru_universes_n = n_distinct(universe), .by = package)

  bind_rows(detail |> semi_join(picked, by = c("package", "universe")), picked) |>
    distinct(package, .keep_all = TRUE) |>
    rename_with(\(x) paste0("ru_", x), -package) |>
    left_join(hosts, by = "package") |>
    mutate(ru_universes_n = coalesce(ru_universes_n, 0)) # 0 = only on the cran mirror
}

# Names in R-multiverse's curated universe (_indexed:false rows, so not in the global search)
fetch_ru_multiverse <- function() {
  paste0(settings$ru_multiverse, "/api/packages?stream=true&fields=Package") |>
    cached_get() |>
    readLines(warn = FALSE, encoding = "UTF-8") |>
    discard(\(line) line == "") |>
    map_chr(\(line) fromJSON(line)$Package)
}

# The highest-scoring packages on r-universe that CRAN doesn't have, at most a few
# per universe (monorepos like PEcAn would otherwise fill the list)
top_not_on_cran <- function(index, db, n = settings$not_on_cran_n, per_universe = settings$not_on_cran_per_universe) {
  index |>
    filter(!package %in% db$Package, !universe %in% settings$not_on_cran_skip) |>
    slice_max(score, n = 1, by = package, with_ties = FALSE) |>
    slice_max(score, n = per_universe, by = universe, with_ties = FALSE) |>
    slice_max(score, n = n, with_ties = FALSE) |>
    select(package, universe, score, stars, dependents, scripts)
}

# NDJSON, one line per system library: {library, usedby: [{owner, package}], ...}
fetch_ru_sysdeps <- function() {
  ru_url("cran", "/api/sysdeps?stream=true") |>
    cached_get() |>
    readLines(warn = FALSE, encoding = "UTF-8") |>
    discard(\(line) line == "") |>
    map(parse_sysdep_line) |>
    list_rbind() |>
    bind_rows(tibble(library = character(), package = character())) |>
    distinct()
}

parse_sysdep_line <- function(line) {
  j <- fromJSON(line)
  tibble(library = j$library %||% NA_character_, package = j$usedby$package %||% character())
}
