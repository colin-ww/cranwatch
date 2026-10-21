# Status, links, flags ---------------------------------------------------------

cran_statuses <- c("cran", "cran-archived")

# First pass, before GitHub: where can you install it from today?
# (archived from CRAN but alive on r-universe, e.g. polars -> "r-universe")
assign_status <- function(snap) {
  snap |>
    mutate(status = case_when(
      package %in% base_pkgs() ~ "base",
      on_cran %in% TRUE        ~ "cran",
      !is.na(ru_universe)      ~ "r-universe",
      cran_archived %in% TRUE  ~ "cran-archived"
    ))
}

# Second pass + derived columns. complete = FALSE (a lookup API failed) turns
# would-be "not-found" into "unknown", so an outage doesn't raise alerts.
finalize <- function(snap, today, complete = TRUE) {
  snap |>
    add_na_cols("ru_hadley", na = NA) |>
    ensure_cols() |>
    mutate(
      run_date   = today,
      hadley     = coalesce(hadley, if_else(ru_hadley %in% TRUE, "contributor", NA_character_)),
      lookups_ok = complete, # (an argument named like the column would be masked by it)
      repo     = coalesce(repo, cran_repo),
      status   = coalesce(status, case_when(
        !is.na(gh_stars) ~ "github",
        complete         ~ "not-found",
        .default         = "unknown"
      )),
      # r-universe first: it has the README, docs and NEWS of CRAN packages too
      link = case_when(
        status == "base"          ~ paste0("https://stat.ethz.ch/R-manual/R-patched/library/", package, "/html/00Index.html"),
        !is.na(ru_universe)       ~ paste0("https://", ru_universe, ".r-universe.dev/", package),
        status %in% cran_statuses ~ paste0(settings$cran_base, "/package=", package),
        status == "github"        ~ paste0("https://github.com/", repo)
      )
    ) |>
    add_flags(today) |>
    conform() |>
    arrange(package)
}

add_flags <- function(snap, today) {
  yes <- \(x) x %in% TRUE

  hits <- with(snap, tibble(
    deadline           = !is.na(deadline),
    archived           = status != "cran" & yes(archived_n > 0), # off CRAN, was on it
    orphaned           = yes(orphaned),
    `archived-past-yr` = status %in% "cran" & yes(archived_last >= today - 365),
    `new-past-yr`      = status %in% "cran" & yes(dl_prev365 == 0 & dl_365 > 0),
    `not-found`        = status %in% "not-found",
    `gh-archived`      = yes(gh_archived),
    `watch-sysreq`     = !is.na(sysreqs_watch)
  ))

  snap |>
    mutate(flags = pmap_chr(hits, \(...) {
      hit <- c(...)
      if (any(hit)) paste(names(hit)[hit], collapse = "; ") else NA_character_
    }))
}
