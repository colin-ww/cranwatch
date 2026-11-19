# Which R packages live outside CRAN?

One-off exploration (Nov 2026), **not** part of the cranwatch workflow. Questions:

- What are the most popular R packages that are not on CRAN, and are they on conda?
- Why aren't they on CRAN?
- How big are CRAN, r-universe, R-multiverse, Bioconductor, conda-forge, R-Forge?

## Run

From the repo root. Everything is bulk downloads (~30 requests, ~80 MB), cached in `_cache/` (gitignored) for a day.

```sh
Rscript explore/not-on-cran/01_index.R        # every r-universe package + CRAN/Bioc/R-multiverse/conda flags
explore/not-on-cran/gh_top.sh                 # top 1000 language:R GitHub repos by stars (needs gh auth)
Rscript explore/not-on-cran/02_rank.R         # rank non-CRAN packages 3 ways
Rscript explore/not-on-cran/03_detail.R       # why not on CRAN: Remotes, non-CRAN deps, size, CRAN comment
Rscript explore/not-on-cran/04_repos_conda.R  # R-Forge & co, Bioc vs CRAN, conda channels
Rscript explore/not-on-cran/05_offstats.R     # official-statistics packages + hand-picked ones
Rscript explore/not-on-cran/06_followups.R    # awesome-offstats not on CRAN, Bioc in deps, RStudio add-ins, ggplot2 gallery
```

`out/` holds the results (except `ru_all_flags.csv`, 4 MB, gitignored).

## Sources

| What | URL |
|---|---|
| r-universe, every package ranked by score | `https://r-universe.dev/api/search?limit=5000&skip=N` |
| r-universe totals | `https://r-universe.dev/api/summary?all=true` |
| r-universe, one package (deps, Remotes, size) | `https://{universe}.r-universe.dev/api/packages/{pkg}` |
| CRAN current / ever / archive reasons | `web/packages/packages.rds`, `src/contrib/Meta/archive.rds`, `src/contrib/PACKAGES.in` |
| Bioconductor | `bioconductor.org/packages/release/{bioc,data/annotation,...}/src/contrib/PACKAGES` |
| R-multiverse | `community.r-multiverse.org/api/packages`, `production.r-multiverse.org/<date>/src/contrib/PACKAGES` |
| conda (every name on a channel) | `conda.anaconda.org/{conda-forge,bioconda,r}/channeldata.json` |
| conda, one name, all channels | `api.anaconda.org/search?name=r-polars&type=conda` |
| Official-statistics software list | `SNStatComp/awesome-official-statistics-software` README |

Overlap with cranwatch: `01_index.R`'s r-universe paging is `ru_search_all()` in `R/runiverse.R`, and the CRAN db is the same file.

## Caveats

- r-universe's score rewards reverse dependencies and the owning repo's stars, so monorepos (PEcAn, ~40 packages) and dev forks (`igraph.dev`) float up. `02_rank.R` keeps one row per universe + star count.
- Popular GitHub-only packages that no universe registers (CellChat, monocle3, ArchR, INLA, bbplot, ggradar…) have no r-universe score at all. GitHub stars catch some of them.
- `scripts` (GitHub code calling `library(pkg)`) gives false matches for generic names (`debug`, `dir`).
- conda names are matched as `r-` + lowercase package name.
