# cranwatch

[![cranwatch](https://github.com/colin-ww/cranwatch/actions/workflows/cranwatch.yml/badge.svg)](https://github.com/colin-ww/cranwatch/actions/workflows/cranwatch.yml)

Health radar for the R packages I use, or am eyeing, at work: how popular they are, whether CRAN is about to archive them, and how painful they are to install somewhere locked down (air-gapped k8s, source-only mirror, no `apt-get`).

**Site → <https://colin-ww.github.io/cranwatch/>**: [Radar](https://colin-ww.github.io/cranwatch/) (the table) · [Themes](https://colin-ww.github.io/cranwatch/themes.html) (what each group of packages is for and what to pick) · [How to judge a package](https://colin-ww.github.io/cranwatch/judge.html) · [Columns & sources](https://colin-ww.github.io/cranwatch/about.html) · [latest CSV](data/latest.csv)

Written for colleagues in a stats office moving from SAS to R, but the method works for anyone's package list.

## What it tracks

Per package in [`packages.yml`](packages.yml):

- **Popularity**: r-universe score + its parts (stars, recursive dependents, scripts, commits, contributors), CRAN downloads for the last 365 days vs the 365 before
- **CRAN health**: current deadline, orphaned, times archived + last date, CRAN's comment, status (`cran` / `cran-archived` / `r-universe` / `github` / `base` / `not-found`)
- **Install burden**: `NeedsCompilation`, recursive deps as *extra (total)* (extra = beyond what `install.packages("tidyverse")` brings; the CSV also names them), whether it's part of a tidyverse install, SystemRequirements (own + "via deps", optional ones marked), libraries r-universe saw it link, hits on [`sys-deps.yml`](sys-deps.yml)
- **Reverse deps**: direct count, plus the top 3 by r-universe score when at least 3 score > 10
- **Behind it**: maintainer (name only), funders, whether Hadley Wickham maintains / authors / contributes to it, which r-universe universes host it, whether it's in R-multiverse
- **Top scoring but not on CRAN**: [`data/not-on-cran.csv`](data/not-on-cran.csv), the best of r-universe that CRAN doesn't have

## How it works

```
1st of the month, 06:17 UTC (or push / manual run)
  └─ Rscript run.R
       ├─ CRAN packages.rds + PACKAGES.in from the cloud CDN   (1 file each)
       ├─ r-universe /api/search pages (every package's score) + per-universe
       │  /api/packages?fields=... (score ingredients) + /api/sysdeps + R-multiverse's list   (~80 requests)
       ├─ cranlogs totals   (2 requests per 50 packages)
       ├─ GitHub API   (only repos not found elsewhere)
       └─ data/snapshots/<date>.csv, data/latest.csv, data/run.json, _alerts/*.md
  ├─ commit data/
  ├─ sync the "cranwatch alerts" issue (open / comment on new / close when clear;
  │  data/alerts.csv remembers what was announced, so each alert is announced once)
  └─ quarto render site → GitHub Pages
```

- **Polite by design**: bulk endpoints (~90 requests/run for 160+ packages + every package's score), responses cached on disk for 20 h and kept between CI runs (GitHub's excepted), a `cranwatch/0.1 (+repo URL)` User-Agent, requests to one host one at a time and ≥ 0.5 s apart, backoff on 429/5xx. Each run's real request counts are in `data/run.json`.
- A source that's down leaves its columns `NA` and is logged in `data/run.json`. Only the CRAN db is required.
- Pull requests do a dry run: tests, a real fetch and a site render, uploaded as an artifact. No commit, issue or deploy.

## Editing the watchlist

- [`packages.yml`](packages.yml): one key per theme. Entries can be `dplyr`, `owner/repo`, or `{pkg: polars, repo: pola-rs/r-polars}`. A trailing `# comment` shows up as that package's note on the site. Push and the workflow re-runs.
- [`guides/<theme>.md`](guides/): the text on the Themes page, plain markdown. Delete the `status: draft` line once a guide has been reviewed and the "draft" badge disappears.
- [`links.yml`](links.yml): things that aren't packages.

## Moving or forking

The repo name is read from `GITHUB_REPOSITORY` when the workflow runs, so most links, the User-Agent and the Pages URL follow it. Four things are written out by hand; change them together (a test fails if they disagree):

- `R/settings.R`: the default for `gh_repo` (only used when running locally)
- `site/_quarto.yml`: `site-url`, `repo-url` and the GitHub icon link
- `README.md`: the badge and the site links

Then Settings → Pages → Source: GitHub Actions, and tick Issues (for the alert issue).

## One-time setup

1. **Settings → Pages → Source: GitHub Actions** (otherwise the deploy job fails)
2. Watch the repo, or rely on the @mention in the alert issue, to get emails

## Run locally

```r
pak::local_install_deps(dependencies = c("all", "Config/Needs/site"))  # deps listed in DESCRIPTION
testthat::test_dir("tests/testthat")                                   # offline, fake sources
source("run.R")                                                        # real fetch -> data/
```

Then `quarto render site` in a terminal (needs the [Quarto CLI](https://quarto.org/docs/get-started/)).

**Locked-down or cloud environment** (a Claude Code cloud session, an air-gapped box): the pipeline is pure R, and every package in `DESCRIPTION` has Linux binaries on Posit Package Manager, so no compiler is needed. The outbound hosts it needs:

- `cloud.r-project.org`, `cranlogs.r-pkg.org`
- `r-universe.dev` **and** `*.r-universe.dev` (the wildcard doesn't cover the bare domain)
- `api.github.com`, only for repos found nowhere else; without a `GITHUB_TOKEN` GitHub answers 403 and those packages show `unknown` (CI has a token)

The Quarto CLI is only needed to render the site, not to produce the CSVs.

## Layout

| Path | What |
|---|---|
| `packages.yml`, `links.yml`, `sys-deps.yml` | Config: watchlist (+ notes as comments), non-package links, system libs to flag |
| `guides/` | One markdown guide per theme, shown on the Themes page |
| `run.R` | Entry point |
| `R/` | Pipeline: `cran.R`, `runiverse.R`, `cranlogs.R`, `github.R` (fetch + metrics per source), `build.R` (status/flags), `alerts.R`, `schema.R` (snapshot columns), `main.R` |
| `tests/testthat/` | Offline tests: unit tests + the full pipeline on fake sources |
| `site/` | Quarto site: Radar (reactable table), Themes, How to judge a package, Columns & sources |
| `data/` | Written by the workflow: `snapshots/<date>.csv`, `latest.csv`, `run.json` (sources, request counts), `alerts.csv` (announced alerts), `not-on-cran.csv` |
| `IDEAS.txt` | Scratchpad |

## Caveats

- Downloads come only from Posit's CRAN mirror and include CI/bots, so treat them as relative.
- r-universe calls its score formula a work in progress (it's documented on the [about page](https://colin-ww.github.io/cranwatch/about.html)). Use the component columns for trends.
- CRAN doesn't publish deadline history, so "had a deadline before" only builds up from the first snapshot on.
