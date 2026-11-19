# 6. Follow-ups: the awesome-official-statistics packages not on CRAN, do the shortlisted packages pull in
# Bioconductor, RStudio add-ins outside CRAN, and the ggplot2 extensions gallery (which entries aren't on CRAN).
source("explore/not-on-cran/helpers.R")
all  <- ru_flags()
db   <- cran_db()
now  <- unique(db$Package)
ever <- cran_ever()
cf   <- conda_names("conda-forge")
why  <- cran_reasons()

# Bioc PACKAGES with dependency fields, so recursive deps can run through CRAN + Bioc
bioc_db <- bioc_repos |>
  map(\(r) tryCatch(read.dcf(get(glue::glue("https://bioconductor.org/packages/release/{r}/src/contrib/PACKAGES")),
                             fields = c("Package", "Version", "Depends", "Imports", "LinkingTo", "Suggests")) |> as_tibble(),
                    error = \(e) NULL)) |>
  list_rbind()
bioc <- unique(bioc_db$Package)
both <- bind_rows(db |> select(Package, Version, Depends, Imports, LinkingTo, Suggests), bioc_db) |>
  distinct(Package, .keep_all = TRUE) |> as.matrix()

where_is <- \(pkg) case_when(pkg %in% now ~ "CRAN", pkg %in% bioc ~ "Bioc", pkg %in% ever ~ "CRAN-archived",
                             pkg %in% all$package ~ "r-universe", .default = "GitHub/other")

# Hard deps of a package not on CRAN, read from its DESCRIPTION wherever it lives
description_deps <- \(desc_url) {
  d <- tryCatch(read.dcf(get(desc_url)) |> as_tibble(), error = \(e) tibble())
  list(strong  = deps_of(paste(d[["Depends"]], d[["Imports"]], d[["LinkingTo"]], sep = ",")),
       suggest = deps_of(d[["Suggests"]] %||% ""))
}
bioc_in <- \(deps) {
  rec <- unique(c(deps$strong, unlist(tools::package_dependencies(deps$strong, db = both, recursive = TRUE))))
  tibble(bioc_hard = paste(intersect(rec, bioc), collapse = " "),
         bioc_suggests = paste(intersect(deps$suggest, bioc), collapse = " "),
         non_cran_hard = paste(setdiff(rec, c(now, bioc, base_pkgs)), collapse = " "))
}
anaconda_channels <- \(pkg) {
  hits <- read_json(paste0("https://api.anaconda.org/search?name=", to_conda(pkg), "&type=conda"))
  if (length(hits)) paste(unique(hits$owner[hits$name == to_conda(pkg)]), collapse = " ") else ""
}

# 1. awesome-official-statistics R packages not on CRAN -----------------------------------------
aw <- read_csv(file.path(out, "awesome_offstats_r.csv"), show_col_types = FALSE) |> filter(where != "CRAN")
crandb <- \(pkg) tryCatch(read_json(paste0("https://crandb.r-pkg.org/", pkg)), error = \(e) list())
aw |>
  mutate(title = map_chr(package, \(p) crandb(p)$Title %||% NA_character_)) |>
  left_join(why, by = "package") |>
  select(section, package, where, title, cran_comment, link) |>
  show(10, 90)

# 2. Shortlist: Bioc anywhere in the dependency tree? conda channels? -----------------------------
ru_desc <- \(universe, pkg) glue::glue("https://{universe}.r-universe.dev/{pkg}/DESCRIPTION")
gh_desc <- \(repo, branch = "master") glue::glue("https://raw.githubusercontent.com/{repo}/{branch}/DESCRIPTION")
shortlist <- tribble(
  ~package,             ~desc_url,
  "ReGenesees",         gh_desc("DiegoZardetto/ReGenesees"),
  "babelquarto",        ru_desc("ropensci", "babelquarto"),
  "INLA",               NA, # its own repo: read from that repo's PACKAGES below
  "cmdstanr",           ru_desc("stan-dev", "cmdstanr"),
  "ganttrify",          ru_desc("giocomai", "ganttrify"),
  "ggannotate",         gh_desc("MattCowgill/ggannotate"),
  "rnaturalearthhires", ru_desc("ropensci", "rnaturalearthhires"),
  "weathercan",         ru_desc("ropensci", "weathercan")
)
inla <- read.dcf(get("https://inla.r-inla-download.org/R/stable/src/contrib/PACKAGES")) |> as_tibble()
inla_deps <- list(strong = deps_of(paste(inla[["Depends"]], inla[["Imports"]], inla[["LinkingTo"]], sep = ",")), suggest = deps_of(inla[["Suggests"]]))

cat("\n== shortlist: Bioc in dependency tree, conda ==\n")
shortlist |>
  mutate(deps = map2(package, desc_url, \(p, u) if (p == "INLA") inla_deps else description_deps(u))) |>
  mutate(map_dfr(deps, bioc_in), anaconda = map_chr(package, anaconda_channels), conda_forge = to_conda(package) %in% cf) |>
  select(-deps, -desc_url) |>
  show(10, 60)

# 3. RStudio add-ins --------------------------------------------------------------------------
addins <- c("regexplain", "ggannotate", "rsthemes", "rscodeio", "shrtcts", "strcode", "prefixer", "remedy",
            "ggThemeAssist", "citr", "wordcountaddin", "mischelper", "codegrip", "pipecleaner", "ViewPipeSteps",
            "datapasta", "esquisse", "addinslist", "todor", "sinew", "viewxl", "colourpicker", "questionr",
            "styler", "reprex", "gptstudio", "ggedit", "ggplotAssist", "listviewer", "snippets", "editheme", "discoverr")
cat("\n== RStudio add-ins ==\n")
tibble(package = addins) |>
  left_join(all |> select(package, universe, score, stars, title), by = "package") |>
  mutate(where = where_is(package), conda_forge = to_conda(package) %in% cf) |>
  arrange(where != "CRAN", desc(score)) |>
  select(package, where, universe, score, stars, conda_forge, title) |>
  show(40, 45)

# 4. ggplot2 extensions gallery -----------------------------------------------------------------
gallery <- yaml::read_yaml(get("https://raw.githubusercontent.com/ggplot2-exts/gallery/gh-pages/_config.yml"))$widgets |>
  map(\(w) tibble(package = w$name, repo = paste0(w$ghuser, "/", w$ghrepo), gallery_cran = isTRUE(w$cran),
                  tags = w$tags %||% NA, short = str_squish(w$short %||% ""))) |>
  list_rbind() |>
  left_join(all |> select(package, universe, score, stars), by = "package") |>
  mutate(where = where_is(package), conda_forge = to_conda(package) %in% cf)
cat("\n== ggplot2 extensions gallery:", nrow(gallery), "entries ==\n")
print(count(gallery, where))
gallery |> filter(where != "CRAN") |> arrange(desc(stars)) |>
  select(package, where, repo, stars, conda_forge, short) |> show(80, 70)
write_csv(gallery, file.path(out, "ggplot2_gallery.csv"))
