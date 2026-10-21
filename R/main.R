# Pipeline ---------------------------------------------------------------------

# Swappable so tests can run the whole pipeline offline with fake sources
default_fetchers <- function() {
  list(
    cran_db    = fetch_cran_db,
    cran_in    = fetch_cran_packages_in,
    ru_index   = fetch_ru_index,
    ru_detail  = fetch_ru_detail,
    ru_sysdeps = fetch_ru_sysdeps,
    ru_multiverse = fetch_ru_multiverse,
    downloads  = fetch_downloads,
    github     = fetch_github
  )
}

main <- function(root = ".", today = Sys.Date(), fetch = default_fetchers(), write = TRUE) {
  http_reset()
  # Each source is optional except the CRAN db: a failure is logged, its columns stay NA
  sources <- list()
  src <- function(name, ...) {
    t0  <- Sys.time()
    out <- tryCatch(fetch[[name]](...), error = identity)
    ok  <- !inherits(out, "error")
    sources[[name]] <<- compact(list(
      ok    = ok,
      secs  = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
      error = if (!ok) conditionMessage(out)
    ))
    msg("{name}: {if (ok) 'ok' else paste('FAILED -', conditionMessage(out))}")
    if (ok) out
  }

  watch     <- read_watchlist(file.path(root, "packages.yml")) |> collapse_themes()
  sys_watch <- read_sys_watch(file.path(root, "sys-deps.yml"))
  msg("{nrow(watch)} packages on the watchlist")

  cran_db <- src("cran_db") %||% stop("CRAN package db unavailable; not writing a snapshot", call. = FALSE)
  cran_in <- src("cran_in")
  index   <- src("ru_index")
  if (!is.null(attr(index, "partial"))) sources$ru_index$partial <- attr(index, "partial")
  detail  <- if (!is.null(index)) src("ru_detail", ru_pick(index, watch))
  if (!is.null(detail)) {
    match <- ru_formula_match(detail)
    if (is.finite(match)) sources$ru_detail$formula_match <- match
    if (length(attr(detail, "failed"))) sources$ru_detail$failed <- attr(detail, "failed")
  }
  sysdeps <- src("ru_sysdeps")
  mv_names <- src("ru_multiverse")

  snap <- list(
    watch,
    cran_metrics(cran_db, cran_in, watch$package),
    ru_metrics(index, detail, watch),
    install_metrics(cran_db, sysdeps, watch$package, sys_watch),
    revdep_metrics(cran_db, index, watch$package, complete = is.null(attr(index, "partial")))
  ) |>
    reduce(left_join, by = "package") |>
    mutate(multiverse = if (!is.null(mv_names)) package %in% mv_names else NA) |>
    assign_status()

  dl <- src("downloads", snap |> filter(status %in% cran_statuses) |> pull(package), today)
  gh <- src("github", snap |> filter(is.na(status), !is.na(repo)) |> pull(repo))

  # Sources that decide status: if one failed, unresolved packages are "unknown"
  # and alerts are incomplete
  degraded <- c("cran_in", "ru_index", "github") |> keep(\(s) !isTRUE(sources[[s]]$ok))

  snap <- snap |>
    left_join(dl %||% tibble(package = character()), by = "package") |>
    left_join(gh %||% tibble(repo = character()), by = "repo") |>
    finalize(today, complete = !length(degraded))

  msg("status: {snap |> count(status) |> glue_data('{status} {n}') |> paste(collapse = ', ')}")
  not_on_cran <- if (!is.null(index)) top_not_on_cran(index, cran_db)
  if (write) write_outputs(snap, root, today, sources, degraded, not_on_cran) else invisible(snap)
}

# What started this run, from the variables GitHub Actions sets ("local" elsewhere)
run_info <- function() {
  event <- Sys.getenv("GITHUB_EVENT_NAME")
  run   <- Sys.getenv("GITHUB_RUN_ID")
  compact(list(
    trigger = switch(event, schedule = "scheduled", workflow_dispatch = "manual", push = "push", pull_request = "pull request", if (nzchar(event)) event else "local"),
    commit  = if (nzchar(Sys.getenv("GITHUB_SHA"))) str_sub(Sys.getenv("GITHUB_SHA"), 1, 7),
    run_url = if (nzchar(run)) glue("https://github.com/{gh_repo}/actions/runs/{run}") |> as.character()
  ))
}

write_outputs <- function(snap, root, today, sources, degraded = character(), not_on_cran = NULL) {
  data_dir <- file.path(root, "data")
  snap_dir <- file.path(data_dir, "snapshots")
  dir.create(snap_dir, recursive = TRUE, showWarnings = FALSE)

  snaps    <- list.files(snap_dir, "^\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE) |> sort()
  date_of  <- \(p) if (length(p)) str_remove(basename(p), "\\.csv$")
  # run.json "previous": the last run on an earlier day
  prev_path <- snaps |> keep(\(p) date_of(p) < as.character(today)) |> tail(1)
  ledger_path <- file.path(data_dir, "alerts.csv")
  ledger      <- read_ledger(ledger_path)

  c(file.path(snap_dir, paste0(today, ".csv")), file.path(data_dir, "latest.csv")) |>
    walk(\(p) write_csv(snap, p, na = ""))

  if (!is.null(not_on_cran)) write_csv(not_on_cran, file.path(data_dir, "not-on-cran.csv"), na = "")

  list(
    run_date   = today,
    run_time   = format(Sys.time(), tz = "UTC", usetz = TRUE),
    run_info   = run_info(),
    previous   = date_of(prev_path),
    dl_windows = dl_windows(today),
    n_packages = nrow(snap),
    sources    = sources,
    requests   = list(sent = as.list(http_log$sent), from_cache = as.list(http_log$cached))
  ) |>
    write_json(file.path(data_dir, "run.json"), auto_unbox = TRUE, pretty = TRUE)

  alerts <- write_alerts(snap, ledger, date_of(prev_path), file.path(root, "_alerts"), degraded)
  update_ledger(ledger, alerts$active, alerts$new, today, complete = !length(degraded)) |>
    write_csv(ledger_path, na = "")
  invisible(snap)
}
