test_that("full pipeline on fake sources", {
  root <- fake_root()
  main(root, test_today, fake_fetchers())
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  row  <- \(p) snap |> filter(package == p)

  expect_true(file.exists(file.path(root, "data", "snapshots", "2026-10-08.csv")))
  expect_equal(
    snap |> select(package, status) |> deframe(),
    c(Rcpp = "cran", alpha = "cran", beta = "cran", delta = "cran", echo = "cran-archived", foxtrot = "r-universe",
      golf = "github", hotel = "not-found", kilo = "cran", stats4 = "base") # dplyr sorts in the C locale
  )

  # themes collapse, r-universe picks the top-scoring universe
  expect_equal(row("alpha")$themes, "core; other")
  expect_equal(row("alpha")$ru_universe, "me")
  expect_equal(row("alpha")$ru_update_weeks, 6) # ingredients come from the detail fetch
  expect_true(is.na(row("beta")$ru_update_weeks)) # ...index-only packages keep the headline numbers
  expect_equal(row("beta")$ru_score, 8)
  expect_equal(row("alpha")$repo, "me/alpha")

  # archive history: Unarchived doesn't count, recent archival flagged
  expect_equal(row("alpha")$archived_n, 1)
  expect_match(row("alpha")$flags, "archived-past-yr")
  expect_equal(row("echo")$archived_last, as.Date("2026-09-01"))

  # install burden: base deps dropped, noise dropped, optional kept, via-deps attributed
  expect_equal(row("alpha")$deps_n, 2)
  expect_equal(row("beta")$sysreqs, "libxml2 (optional); glpk (>= 4.57, optional)")
  expect_match(row("alpha")$sysreqs_via_deps, "libxml2 (optional) [beta]", fixed = TRUE)
  expect_equal(row("alpha")$sysdeps_detected, "glpk; libxml2")
  expect_equal(row("alpha")$sysreqs_watch, "libxml2")
  expect_equal(row("delta")$sysreqs_watch, "cmake")

  # revdeps
  expect_equal(row("alpha")$revdeps_n, 4)
  expect_equal(row("alpha")$revdeps_notable_n, 3)
  expect_equal(row("alpha")$revdeps_top, "rev2 (20), rev1 (15), rev3 (11)")

  # downloads + flags
  expect_match(row("delta")$flags, "deadline")
  expect_match(row("delta")$flags, "new-past-yr")
  expect_true(is.na(row("stats4")$dl_365))

  # alerts: first run -> everything is new
  active <- readLines(file.path(root, "_alerts", "active.md"))
  expect_true(any(str_detect(active, "\\| delta \\| deadline")))
  expect_true(any(str_detect(active, "\\| echo \\| archived")))
  expect_true(any(str_detect(active, "\\| kilo \\| orphaned")))
  expect_false(any(str_detect(active, "hotel")))                 # not-found: a flag + site to-do, not an alert
  expect_match(row("hotel")$flags, "not-found")
  expect_length(readLines(file.path(root, "_alerts", "new.md")) |> str_subset("^- "), 3)
})

test_that("second run only reports what changed", {
  root <- fake_root()
  main(root, test_today - 7, fake_fetchers())
  db2 <- fake_db |> mutate(
    Deadline   = if_else(Package == "beta", "2026-11-01", Deadline),
    Maintainer = if_else(Package == "beta", "ORPHANED", "someone")
  )
  main(root, test_today, fake_fetchers(cran_db = \() add_na_cols(db2, cran_fields)))

  new <- readLines(file.path(root, "_alerts", "new.md")) |> str_subset("^- ")
  expect_equal(new, c("- **beta**: CRAN deadline 2026-11-01", "- **beta**: orphaned on CRAN (no maintainer)"))
  expect_equal(fromJSON(file.path(root, "data", "run.json"))$previous, "2026-10-01")
})

test_that("a failed lookup source gives 'unknown', not 'not-found' alerts", {
  root <- fake_root()
  main(root, test_today, fake_fetchers(ru_index = \() stop("r-universe down")))
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))

  expect_equal(snap$status[snap$package %in% c("foxtrot", "hotel")], c("unknown", "unknown"))
  expect_true(all(is.na(snap$ru_score)))
  expect_false(fromJSON(file.path(root, "data", "run.json"))$sources$ru_index$ok)
})

test_that("no CRAN db -> no snapshot", {
  root <- fake_root()
  expect_error(main(root, test_today, fake_fetchers(cran_db = \() stop("CRAN down"))), "not writing")
  expect_false(dir.exists(file.path(root, "data")))
})

test_that("a same-day re-run doesn't re-announce", {
  root <- fake_root()
  main(root, test_today, fake_fetchers())
  expect_true(file.exists(file.path(root, "_alerts", "new.md")))
  main(root, test_today, fake_fetchers())
  expect_false(file.exists(file.path(root, "_alerts", "new.md")))
  expect_true(file.exists(file.path(root, "_alerts", "active.md")))
})

test_that("an outage doesn't announce, close, or re-announce afterwards", {
  root <- fake_root()
  main(root, test_today - 14, fake_fetchers())                                     # complete
  main(root, test_today - 7, fake_fetchers(ru_index = \() stop("r-universe down"))) # outage
  expect_true(file.exists(file.path(root, "_alerts", "degraded")))
  expect_false(file.exists(file.path(root, "_alerts", "new.md")))
  expect_match(paste(readLines(file.path(root, "_alerts", "active.md")), collapse = "\n"), "Partial data: ru_index")

  main(root, test_today, fake_fetchers())                                           # recovered
  expect_false(file.exists(file.path(root, "_alerts", "degraded")))
  expect_false(file.exists(file.path(root, "_alerts", "new.md"))) # nothing new: the outage changed no alert
})

test_that("a GitHub error makes unresolved packages unknown, not not-found", {
  root <- fake_root()
  main(root, test_today, fake_fetchers(github = \(repos) stop("GitHub API 403 for own/golf")))
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  expect_equal(snap$status[snap$package %in% c("golf", "hotel")], c("unknown", "unknown"))
})

test_that("run.json records request counts", {
  root <- fake_root()
  main(root, test_today, fake_fetchers())
  expect_true(all(c("sent", "from_cache") %in% names(fromJSON(file.path(root, "data", "run.json"))$requests)))
})

test_that("a new alert during an outage is announced then, and not again after", {
  root <- fake_root()
  writeLines(c("core:", "  - alpha", "  - beta", "  - delta"), file.path(root, "packages.yml")) # all CRAN: nothing turns "unknown"
  db2 <- fake_db |> mutate(Deadline = if_else(Package == "beta", "2026-11-01", Deadline))

  main(root, test_today - 14, fake_fetchers())
  main(root, test_today - 7, fake_fetchers(ru_index = \() stop("down"), cran_db = \() add_na_cols(db2, cran_fields)))
  expect_equal(readLines(file.path(root, "_alerts", "new.md")) |> str_subset("^- "), "- **beta**: CRAN deadline 2026-11-01")

  main(root, test_today, fake_fetchers(cran_db = \() add_na_cols(db2, cran_fields)))
  expect_false(file.exists(file.path(root, "_alerts", "new.md")))
})

test_that("alerts announced during an outage aren't repeated when it ends; what it hid is announced then", {
  root <- fake_root()
  lines <- \() readLines(file.path(root, "_alerts", "new.md")) |> str_subset("^- ")
  main(root, test_today - 7, fake_fetchers(cran_in = \() stop("PACKAGES.in down"))) # first ever run is partial: no archive history
  expect_equal(lines(), c("- **delta**: CRAN deadline 2026-10-20", "- **kilo**: orphaned on CRAN (no maintainer)"))
  expect_false(any(str_detect(readLines(file.path(root, "_alerts", "active.md")), "echo")))
  main(root, test_today, fake_fetchers())
  expect_equal(lines(), "- **echo**: Archived on 2026-09-01 as check problems were not corrected in time.")
})

test_that("the ledger survives a same-day partial re-run", {
  root <- fake_root()
  main(root, test_today - 7, fake_fetchers())                                              # all announced
  main(root, test_today - 7, fake_fetchers(cran_in = \() stop("PACKAGES.in down")))        # same day, partial: overwrites the snapshot
  main(root, test_today, fake_fetchers())
  expect_false(file.exists(file.path(root, "_alerts", "new.md")))
  ledger <- read_ledger(file.path(root, "data", "alerts.csv"))
  expect_true(all(c("kilo", "delta", "echo") %in% ledger$package))
  expect_true("" %in% ledger$when) # orphaned has no date; must round-trip as "", not NA
})

test_that("old archivals are history, not alerts", {
  snap <- tibble(run_date = test_today, package = c("recent", "old"), flags = "archived",
                 archived_last = test_today - c(10, 200), cran_comment = NA_character_, deadline = as.Date(NA), repo = NA_character_)
  expect_equal(alerts_of(snap)$package, "recent")
})

test_that("a complete run forgets resolved alerts, so they can come back", {
  root <- fake_root()
  main(root, test_today - 14, fake_fetchers())
  no_deadline <- fake_db |> mutate(Deadline = NA_character_)
  main(root, test_today - 7, fake_fetchers(cran_db = \() add_na_cols(no_deadline, cran_fields)))
  expect_false("delta" %in% read_ledger(file.path(root, "data", "alerts.csv"))$package[read_ledger(file.path(root, "data", "alerts.csv"))$type == "deadline"])
  main(root, test_today, fake_fetchers())
  expect_true(any(str_detect(readLines(file.path(root, "_alerts", "new.md")), "delta")))
})

test_that("people, curation and install-set columns", {
  root <- fake_root()
  main(root, test_today, fake_fetchers())
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  row  <- \(p) snap |> filter(package == p)

  # people: CRAN maintainer (no email), Hadley as maintainer / author, funders
  expect_equal(row("alpha")$maintainer, "Hadley Wickham")
  expect_equal(row("alpha")$hadley, "maintainer")
  expect_equal(row("alpha")$funders, "Posit Software, PBC")
  expect_equal(row("Rcpp")$hadley, "author")
  expect_equal(row("delta")$maintainer, "Dee Person")
  expect_true(is.na(row("beta")$hadley))
  expect_equal(row("kilo")$maintainer, "ORPHANED")
  expect_false(any(str_detect(snap$maintainer, "@"), na.rm = TRUE))

  # r-universe: every universe hosting the name (the cran mirror aside), R-multiverse
  expect_equal(row("alpha")$ru_universes, "fork; me")
  expect_equal(row("alpha")$ru_universes_n, 2)
  expect_equal(row("foxtrot")$ru_universes, "other; someone")
  expect_equal(row("beta")$ru_universes_n, 0)
  expect_equal(snap$multiverse[snap$package %in% c("alpha", "beta")], c(FALSE, TRUE))

  # install set: beyond what install.packages("tidyverse") brings (= Rcpp here), the deps themselves
  expect_equal(row("alpha")$deps_n, 2)
  expect_equal(row("alpha")$deps_extra_n, 1)
  expect_equal(row("alpha")$deps, "Rcpp; beta")
  expect_equal(row("delta")$deps_extra_n, 0)
  expect_equal(row("Rcpp")$tidyverse, "member")
  expect_true(is.na(row("alpha")$tidyverse))

  # top scorers r-universe has but CRAN doesn't: no Bioconductor, no cran mirror, no CRAN packages
  expect_equal(read_csv(file.path(root, "data", "not-on-cran.csv"), show_col_types = FALSE)$package, c("golf2", "foxtrot"))
})

test_that("Hadley as an r-universe contributor, when CRAN's fields don't mention him", {
  root <- fake_root()
  db2 <- fake_db |> mutate(Maintainer = "Someone Else <s@example.org>", Author = "Someone Else [aut, cre]")
  main(root, test_today, fake_fetchers(cran_db = \() add_na_cols(db2, cran_fields)))
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  expect_equal(snap$hadley[snap$package == "alpha"], "contributor") # from the detail fetch
  expect_true(is.na(snap$hadley[snap$package == "beta"]))
})

test_that("R-multiverse and tidyverse lookups are optional", {
  root <- fake_root()
  main(root, test_today, fake_fetchers(ru_multiverse = \() stop("down")))
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  expect_true(all(is.na(snap$multiverse)))
  expect_false(fromJSON(file.path(root, "data", "run.json"))$sources$ru_multiverse$ok)
  expect_false(file.exists(file.path(root, "_alerts", "degraded"))) # doesn't decide any status or alert

  no_tv <- fake_db |> filter(Package != "tidyverse")
  main(root, test_today, fake_fetchers(cran_db = \() add_na_cols(no_tv, cran_fields)))
  snap <- read_snapshot(file.path(root, "data", "latest.csv"))
  expect_true(all(is.na(snap$deps_extra_n)))  # baseline unknown, not "all of them"
  expect_equal(snap$deps_n[snap$package == "alpha"], 2)
})

test_that("run.json says what started the run", {
  root <- fake_root()
  withr::local_envvar(GITHUB_EVENT_NAME = "schedule", GITHUB_SHA = "abcdef1234567890", GITHUB_RUN_ID = "42", GITHUB_REPOSITORY = "me/cranwatch")
  main(root, test_today, fake_fetchers())
  info <- fromJSON(file.path(root, "data", "run.json"))$run_info
  expect_equal(info$trigger, "scheduled")
  expect_equal(info$commit, "abcdef1")
  expect_match(info$run_url, "/actions/runs/42$")

  withr::local_envvar(GITHUB_EVENT_NAME = "workflow_dispatch")
  expect_equal(run_info()$trigger, "manual")
  withr::local_envvar(GITHUB_EVENT_NAME = "", GITHUB_SHA = "", GITHUB_RUN_ID = "")
  expect_equal(run_info(), list(trigger = "local"))
})
