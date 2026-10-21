# Alerts: flags worth a GitHub issue + what's new since the previous snapshot --

# One row per (package, alert). `when` makes a moved deadline / re-archival count as new.
# Old archivals are known history: shown on the site, but they don't hold the
# issue open.
alerts_of <- function(snap) {
  if (is.null(snap)) return(tibble(package = character(), type = character(), when = character(), detail = character()))

  snap |>
    separate_longer_delim(flags, "; ") |>
    filter(flags %in% settings$alert_types, !(flags == "archived" & coalesce(archived_last < run_date - settings$alert_archived_days, FALSE))) |>
    transmute(
      package,
      type   = flags,
      when   = case_when(
        type == "deadline" ~ as.character(deadline),
        type == "archived" ~ as.character(archived_last),
        .default           = ""
      ),
      detail = case_when(
        type == "deadline" ~ paste("CRAN deadline", deadline),
        type == "archived" ~ coalesce(cran_comment, paste("Archived on CRAN", archived_last)),
        type == "orphaned" ~ "orphaned on CRAN (no maintainer)"
      ) |> str_replace_all("\\|", "/")
    )
}

# The ledger (data/alerts.csv) remembers every alert that has been announced,
# so each one is announced once: across same-day re-runs, outages, anything.
# A complete run forgets alerts that are no longer flagged (so they can be
# announced again if they come back); a partial run forgets nothing.
alert_keys <- c("package", "type", "when")

read_ledger <- function(path) {
  empty <- tibble(package = character(), type = character(), when = character(), first_seen = character())
  if (!file.exists(path)) return(empty)
  read_csv(path, col_types = cols(.default = col_character()), na = character(), show_col_types = FALSE) |>
    bind_rows(empty)
}

update_ledger <- function(ledger, active, new, today, complete) {
  kept <- if (complete) semi_join(ledger, active, by = alert_keys) else ledger
  bind_rows(kept, new |> transmute(package, type, when, first_seen = as.character(today))) |>
    distinct(across(all_of(alert_keys)), .keep_all = TRUE) |>
    arrange(package, type)
}

# Flagged now and not yet announced
new_alerts <- function(snap, ledger) {
  alerts_of(snap) |> anti_join(ledger, by = alert_keys)
}

# Files for the workflow's issue step (.github/scripts/sync-alert-issue.sh):
#   active.md   issue body: everything flagged now
#   new.md      comment: alerts not announced before, which @mentions you
#   degraded    present when a lookup source failed: alerts may be incomplete,
#               so the script won't close the issue
write_alerts <- function(snap, ledger, prev_date, dir, degraded = character(), mention = Sys.getenv("ALERT_MENTION")) {
  unlink(dir, recursive = TRUE)
  dir.create(dir, showWarnings = FALSE)

  active <- alerts_of(snap)
  new    <- new_alerts(snap, ledger)
  cc     <- if (nzchar(mention)) paste0("cc @", mention) else ""

  if (length(degraded)) writeLines(degraded, file.path(dir, "degraded"))

  if (nrow(active)) writeLines(c(
    glue("## cranwatch alerts ({snap$run_date[1]})"), "",
    "| package | alert | details |", "|---|---|---|",
    glue("| {active$package} | {active$type} | {active$detail} |"), "",
    if (length(degraded)) c(glue("_Partial data: {paste(degraded, collapse = ', ')} failed this run, so some alerts may be missing._"), ""),
    glue("_Updated by the scheduled [cranwatch]({settings$site_url}) run; closes itself when nothing is flagged._ {cc}")
  ), file.path(dir, "active.md"))

  if (nrow(new)) writeLines(c(
    if (is.null(prev_date)) glue("New alerts: {cc}") else glue("New since the {prev_date} run: {cc}"), "",
    glue("- **{new$package}**: {new$detail}")
  ), file.path(dir, "new.md"))

  msg("alerts: {nrow(active)} active, {nrow(new)} new{if (length(degraded)) ' (partial data)' else ''}")
  invisible(list(active = active, new = new))
}
