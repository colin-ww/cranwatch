# 5. Packages a stats-office R user might want: where do they live?
# (a) every R package on the awesome-official-statistics-software list, (b) hand-picked ones by theme.
source("explore/not-on-cran/helpers.R")
all    <- ru_flags()
now    <- cran_now()
ever   <- cran_ever()
rforge <- dcf_pkgs("https://R-Forge.R-project.org/src/contrib/PACKAGES")
cf     <- conda_names("conda-forge")

where_is <- \(df) df |>
  left_join(all |> select(package, universe, score, stars, multiverse, title), by = "package") |>
  mutate(where = case_when(package %in% now ~ "CRAN",
                           package %in% ever ~ "CRAN-archived",
                           !is.na(universe) ~ "r-universe",
                           package %in% rforge ~ "R-Forge",
                           .default = "GitHub/other"),
         conda_forge = to_conda(package) %in% cf)

aw <- read_lines(get("https://raw.githubusercontent.com/SNStatComp/awesome-official-statistics-software/master/README.md")) |>
  str_replace_all(c("&#x2F;" = "/", "&#x3D;" = "=", "&amp;" = "&")) |>
  as_tibble_col("l") |>
  mutate(section = if_else(str_starts(l, "####"), str_squish(str_remove_all(l, "^#+|\\(\\[GSBPM.*")), NA)) |>
  fill(section) |>
  filter(str_detect(l, "^R package \\[")) |>
  mutate(package = str_match(l, "^R package \\[([^]]+)\\]")[, 2], link = str_match(l, "^R package \\[[^]]+\\]\\(([^)]+)\\)")[, 2]) |>
  select(section, package, link) |>
  where_is()
cat("== awesome-official-statistics R packages:", nrow(aw), "==\n"); print(count(aw, where))
aw |> filter(where != "CRAN") |> select(section, package, where, universe, conda_forge, link) |> show()
write_csv(aw, file.path(out, "awesome_offstats_r.csv"))

picks <- tribble(
  ~theme,                       ~package,
  "seasonal / benchmarking",    "rjd3toolkit rjd3x13 rjd3tramoseats rjd3bench rjd3filters rjd3nowcasting ggdemetra3 RJDemetra seasonal gseries tempdisagg disaggR",
  "Canada data / maps",         "cansim cancensus tongfen canpumf cmhc statcanR mountainmathHelpers mapcan weathercan tidyhydat bcdata bcmaps rnaturalearthhires canadianmaps",
  "survey / weighting",         "ReGenesees survey srvyr svrep surveysd icarus gustave vardpoor laeken PracTools sampling mase emdi autumn anesrake",
  "editing / imputation / SDC", "validate errorlocate deductive dcmodify simputation VIM rspa lumberjack sdcMicro sdcTable simPop banff",
  "big data / formats",         "polars tidypolars sedonadb duckplyr arrow nanoparquet ROracle readsas",
  "dataviz",                    "ggradar bbplot ggthemr ganttrify ggmagnify ggsankey ggannotate ggchicklet streamgraph reactablefmtr ggalt ggflags emo ggpomological charter ggbrace tidycharts ComplexHeatmap",
  "reporting / bilingual",      "babelquarto babeldown datadrivencv pagedreport xaringanExtra",
  "dev tools",                  "revdepcheck vscDebugger sess colorout regexplain rscodeio gpttools flir",
  "models",                     "cmdstanr rethinking INLA synthdid HonestDiD fwildclusterboot sl3 tmle3 mlr3extralearners catboost gamlss2"
) |>
  separate_longer_delim(package, " ") |>
  where_is()
cat("\n== hand-picked ==\n")
picks |> select(theme, package, where, universe, score, stars, multiverse, conda_forge, title) |> show(120, 40)
write_csv(picks, file.path(out, "picks.csv"))
