test_that("SystemRequirements split keeps commas inside parentheses", {
  expect_equal(
    split_sysreqs("libxml2 (optional), glpk (>= 4.57, optional);  GNU make")[[1]],
    c("libxml2 (optional)", "glpk (>= 4.57, optional)", "GNU make")
  )
})

test_that("archive dates skip 'Unarchived on'", {
  expect_equal(
    archive_dates("Archived on 2023-01-02 as x.\nUnarchived on 2023-02-03. archived on 2024-05-06")[[1]],
    as.Date(c("2023-01-02", "2024-05-06"))
  )
})

test_that("watchlist entries: name, owner/repo, {pkg, repo}", {
  expect_equal(parse_entry("dplyr"), tibble(package = "dplyr", repo = NA_character_))
  expect_equal(parse_entry("cmmr/jobqueue"), tibble(package = "jobqueue", repo = "cmmr/jobqueue"))
  expect_equal(parse_entry(list(pkg = "polars", repo = "pola-rs/r-polars")), tibble(package = "polars", repo = "pola-rs/r-polars"))
})

test_that("real packages.yml parses and every entry has a name", {
  watch <- read_watchlist(test_path("../../packages.yml")) |> collapse_themes()
  expect_gt(nrow(watch), 100)
  expect_false(anyNA(watch$package))
  expect_false(anyDuplicated(watch$package) > 0)
})

test_that("sys watch hits are whole-word and case-insensitive", {
  expect_equal(watch_hits(c("LibXML2 (>= 2.9)", "libxml2-dev", "libxml22", NA), c("libxml2", "cmake")),
               c("libxml2", "libxml2", NA, NA))
})

test_that("top revdeps need enough notable ones", {
  expect_equal(top_revdeps(c("a", "b", "c", "d"), c(11, 30, 12, 5)), "b (30), c (12), a (11)")
  expect_true(is.na(top_revdeps(c("a", "b"), c(11, 30))))
})

test_that("snapshots round-trip and old ones gain new columns", {
  path <- tempfile(fileext = ".csv")
  tibble(package = "x", ru_score = 1.5, run_date = test_today) |> conform() |> write_csv(path, na = "")
  back <- read_snapshot(path)
  expect_named(back, names(snapshot_cols))
  expect_equal(back$ru_score, 1.5)
  expect_s3_class(back$deadline, "Date")
})

test_that("cached_get reuses a fresh file without touching the network", {
  dir  <- tempfile("cache-")
  url  <- "https://example.invalid/data.json"
  path <- file.path(dir, rlang::hash(url))
  dir.create(dir)
  writeLines("{}", path)

  expect_equal(cached_get(url, dir = dir), path) # fresh: no request (example.invalid would fail)
  Sys.setFileTime(path, Sys.time() - 48 * 3600)
  expect_error(cached_get(url, dir = dir))       # stale: tries the network
})

test_that("YAML comments become per-entry and per-theme notes", {
  path <- tempfile(fileext = ".yml")
  writeLines(c(
    "# file header, ignored",
    "pipelines: # see targetopia",
    "  - targets",
    "  - igraph # dep for targets",
    "  - {pkg: polars, repo: pola-rs/r-polars} # not on CRAN",
    "  - cmmr/jobqueue # gh"
  ), path)
  expect_equal(
    read_watch_notes(path),
    tibble(theme = "pipelines", package = c(NA, "igraph", "polars", "jobqueue"),
           note = c("see targetopia", "dep for targets", "not on CRAN", "gh"))
  )
  expect_equal(theme_slug(c("lint/style", "dplyr backends", "data-cleaning")), c("lint-style", "dplyr-backends", "data-cleaning"))
})

test_that("fmt_short rounds each value on its own", {
  expect_equal(fmt_short(c(4890, 209, 39438, 1234567, 12, NA)), c("4.9K", "210", "39K", "1.2M", "12", ""))
})

test_that("GitHub: repo-level errors = not found, GitHub-wide errors stop the source", {
  fake <- \(codes, remaining = "4999") \(...) response(
    status_code = codes[[paste(c(...), collapse = "/")]] %||% 200,
    headers = list(`Content-Type` = "application/json", `x-ratelimit-remaining` = remaining), body = charToRaw("{}")
  )
  expect_equal(gh_repo_info("o/r", fake(list(`repos/o/r` = 404))), tibble(repo = "o/r"))
  expect_equal(gh_repo_info("o/r", fake(list(`repos/o/r` = 451))), tibble(repo = "o/r"))
  blocked <- \(...) response(status_code = 403, body = charToRaw('{"message":"Repository access blocked","block":{"reason":"tos"}}'))
  expect_equal(gh_repo_info("o/r", blocked), tibble(repo = "o/r"))
  expect_error(gh_repo_info("o/r", fake(list(`repos/o/r` = 403), remaining = "0")), "GitHub API 403") # rate limit
  expect_error(gh_repo_info("o/r", fake(list(`repos/o/r` = 403))), "GitHub API 403")                  # bare 403: GitHub-wide
  expect_error(gh_repo_info("o/r", fake(list(`repos/o/r` = 502))), "GitHub API 502")
  latin1 <- \(...) response(status_code = 403, headers = list(`Content-Type` = "text/html"),
                            body = iconv("Acc\u00e8s refus\u00e9", "UTF-8", "latin1", toRaw = TRUE)[[1]])
  expect_error(gh_repo_info("o/r", latin1), "GitHub API 403")                                        # unreadable body
  expect_true(is.na(gh_repo_info("o/r", fake(list(`repos/o/r/contents/DESCRIPTION` = 502)))$gh_is_pkg))
  expect_false(gh_repo_info("o/r", fake(list(`repos/o/r/contents/DESCRIPTION` = 404)))$gh_is_pkg)
})

test_that("archive dates: impossible dates are NA, 'Archived again' counts", {
  out <- archive_dates(c("Archived on 2020-02-30\nUnarchived on 2020-03-12.", "Archived again on 2021-05-01. Archived on 2019-01-02"))
  expect_equal(out[[1]], as.Date(NA))
  expect_equal(out[[2]], as.Date(c("2021-05-01", "2019-01-02")))
})

test_that("requests to one host are spaced out", {
  http_reset()
  t0 <- Sys.time()
  for (i in 1:3) try(perform_polite(request("https://example.invalid/x") |> req_timeout(1)), silent = TRUE)
  expect_gte(as.numeric(Sys.time() - t0, units = "secs"), 2 / settings$max_req_per_sec - 0.05)
  expect_equal(http_log$sent[["example.invalid"]], 3)
  http_reset()
})

test_that("watch flags see requirement items that the display hides", {
  db <- tibble(Package = c("v8ish", "user"), NeedsCompilation = "yes",
               SystemRequirements = c("On Linux you can build against libv8-dev (Debian) or v8-devel (Fedora)", NA),
               Depends = NA_character_, Imports = c(NA, "v8ish"), LinkingTo = NA_character_)
  out <- install_metrics(db, NULL, c("v8ish", "user"), c("libv8", "cmake"))
  expect_equal(out$sysreqs_watch, c("libv8", "libv8"))
})

test_that("funders come from the Author field's fnd role", {
  expect_equal(author_funders("Hadley Wickham [aut, cre] (<https://orcid.org/0000-0003-4757-117X>), Posit Software, PBC [cph, fnd] (ROR: <https://ror.org/03wc8by49>)"), "Posit Software, PBC")
  expect_equal(author_funders("A B [aut, cre], Some Fund [fnd], Other Org [cph, fnd], C D [ctb]"), "Some Fund; Other Org")
  expect_true(is.na(author_funders("A B [aut, cre], C D [ctb]")))
  expect_true(is.na(author_funders("A B and C D"))) # no roles at all
  expect_true(is.na(author_funders(NA_character_)))
})

test_that("tidyverse roles: core, member, dep", {
  tv <- list(direct = c("dplyr", "rvest"), all = c("dplyr", "rvest", "rlang"))
  expect_equal(tidyverse_role(c("ggplot2", "rvest", "rlang", "data.table", "tidyverse"), tv), c("core", "member", "dep", NA, "core"))
  expect_equal(tidyverse_role("dplyr", tv), "core") # core wins over member
  expect_equal(tidyverse_role(c("a", "b"), NULL), c(NA_character_, NA_character_))
})

test_that("reverse-dependency scores are whole numbers", {
  expect_equal(top_revdeps(c("a", "b", "c"), c(21.3, 15.6, 10.2), list(revdep_min_score = 10, revdep_min_n = 3, revdep_top_n = 3)), "a (21), b (16), c (10)")
})
