# 3. Why isn't it on CRAN? One r-universe record per shortlisted package (Remotes, non-CRAN hard deps,
# size, SystemRequirements) + CRAN's archive comment. Also: how many CRAN packages hard-depend on Bioc.
source("explore/not-on-cran/helpers.R")
all  <- ru_flags()
okay <- c(cran_now(), base_pkgs)

shortlist <- c("TwoSampleMR", "polars", "PEcAn.DB", "ospsuite", "sl3", "FIMS", "weathercan", "FLCore", "epinowcast",
               "htmltomarkdown", "BPCells", "tidypolars", "cmdstanr", "rnoaa", "rethinking", "DoubletFinder",
               "nichenetr", "spDataLarge", "rnaturalearthhires", "mlr3extralearners", "tmle3", "sess", "lasR", "sedonadb")

detail <- all |>
  filter(package %in% shortlist) |>
  select(package, universe, cran_comment) |>
  pmap(\(package, universe, cran_comment) {
    d <- read_json(glue::glue("https://{universe}.r-universe.dev/api/packages/{package}"), simplifyVector = FALSE)
    by_role <- \(roles) d$`_dependencies` |> keep(\(x) x$role %in% roles) |> map_chr("package")
    tibble(package, universe, version = d$Version %||% NA,
           size_mb        = round(as.numeric(d$`_filesize` %||% NA) / 1e6, 1),
           remotes        = paste(unlist(d$Remotes), collapse = " "),
           noncran_strong = paste(setdiff(by_role(c("Depends", "Imports", "LinkingTo")), okay), collapse = " "),
           noncran_sugg   = paste(setdiff(by_role("Suggests"), okay), collapse = " "),
           sysreq         = str_squish(d$SystemRequirements %||% ""),
           cran_comment, url = d$RemoteUrl %||% NA)
  }) |>
  list_rbind()
detail |> select(-url) |> show(30, 60)
write_csv(detail, file.path(out, "detail.csv"))

# CRAN's rule: Depends/Imports/LinkingTo must be CRAN or Bioc. How many lean on Bioc?
db   <- cran_db()
bioc <- bioc_pkgs()
strong <- db |>
  select(Package, Depends, Imports, LinkingTo) |>
  pivot_longer(-Package, values_drop_na = TRUE) |>
  mutate(dep = map(value, deps_of)) |>
  unnest(dep) |>
  distinct(Package, dep)
cat("\nCRAN pkgs with a strong dep that is not CRAN/base:", n_distinct(strong$Package[!strong$dep %in% okay]), "\n")
cat("CRAN pkgs with an Additional_repositories field:", sum(!is.na(db$Additional_repositories)), "\n")
cat("CRAN pkgs with NeedsCompilation: yes:", sum(db$NeedsCompilation == "yes", na.rm = TRUE), "\n")
cat("\nBioc pkgs most often hard-required by CRAN pkgs:\n")
strong |> filter(dep %in% bioc) |> count(dep, sort = TRUE) |> show(15)
cat("\nHighest-scoring CRAN pkgs that hard-require Bioc:\n")
strong |>
  filter(dep %in% bioc) |>
  summarise(bioc_deps = paste(dep, collapse = " "), .by = Package) |>
  left_join(all |> select(Package = package, score, title), by = "Package") |>
  arrange(desc(score)) |> show(30)
