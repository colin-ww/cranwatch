# CRAN: package db, archive notes, dependencies ------------------------------

cran_fields <- c(
  "Title", "Version", "Published", "Deadline", "NeedsCompilation", "SystemRequirements",
  "URL", "BugReports", "Maintainer", "Author", "X-CRAN-Comment", "X-CRAN-History", "Depends", "Imports", "LinkingTo"
)

# All current CRAN packages, every DESCRIPTION field + CRAN's own (Deadline, X-CRAN-*).
# Same file tools::CRAN_package_db() reads, fetched ourselves so it gets our UA
# + cache (and doesn't depend on options(repos), which may point at PPM/Artifactory)
fetch_cran_db <- function() {
  paste0(settings$cran_base, "/web/packages/packages.rds") |>
    cached_get() |>
    readRDS() |>
    as_tibble(.name_repair = "unique_quiet") |> # the db has a duplicated MD5sum column
    distinct(Package, .keep_all = TRUE) |>
    add_na_cols(cran_fields)
}

# CRAN's master list incl. archived packages: "Archived on <date> as ..." notes
fetch_cran_packages_in <- function() {
  paste0(settings$cran_base, "/src/contrib/PACKAGES.in") |>
    cached_get() |>
    read.dcf(fields = c("Package", "X-CRAN-Comment", "X-CRAN-History")) |>
    as_tibble() |>
    transmute(package = Package, comment = `X-CRAN-Comment`, history = `X-CRAN-History`) |>
    mutate(across(everything(), \(x) iconv(x, "UTF-8", "UTF-8", sub = ""))) |> # drop stray non-UTF-8 bytes
    filter(!is.na(package))
}

# Release info, deadline, archive history -> one row per watched package known to CRAN
cran_metrics <- function(db, cran_in, pkgs) {
  have_in <- !is.null(cran_in) # without PACKAGES.in archive history is unknown (NA), not 0
  cran_in <- cran_in %||% tibble(package = character(), comment = character(), history = character())
  current <- db |> filter(Package %in% pkgs)

  archive <- bind_rows(
    current |> transmute(package = Package, comment = `X-CRAN-Comment`, history = `X-CRAN-History`),
    cran_in |> filter(package %in% pkgs)
  ) |>
    mutate(date = archive_dates(paste(comment, history))) |>
    unnest_longer(date, keep_empty = TRUE) |>
    summarise(
      archived_n    = n_distinct(date, na.rm = TRUE),
      archived_last = max_or_na(date),
      cran_comment  = first(na.omit(comment), default = NA_character_) |> str_squish() |> str_trunc(300),
      .by = package
    )

  current |>
    transmute(
      package           = Package,
      title             = str_squish(Title),
      version           = Version,
      published         = as.Date(Published),
      deadline          = as.Date(Deadline),
      needs_compilation = NeedsCompilation %in% "yes",
      orphaned          = Maintainer %in% "ORPHANED",
      maintainer        = str_remove(Maintainer, "\\s*<[^>]*>\\s*$") |> str_squish(), # name only, no email
      hadley            = case_when(
        str_detect(Maintainer, hadley_name) ~ "maintainer",
        str_detect(Author, hadley_name)     ~ "author"
      ),
      funders           = author_funders(Author),
      cran_repo         = gh_repo_from(paste(URL, BugReports)),
      on_cran           = TRUE
    ) |>
    full_join(archive, by = "package") |>
    mutate(
      on_cran       = on_cran %in% TRUE,
      cran_archived = !on_cran & package %in% cran_in$package,
      archived_n    = if (have_in) archived_n else NA_real_,
      archived_last = if (have_in) archived_last else as.Date(NA)
    )
}

hadley_name <- "Hadley Wickham"

# Who funds it: DESCRIPTION's Author field marks funders with the role "fnd",
# e.g. "Posit Software, PBC [cph, fnd]" (the structured Authors@R isn't evaluated)
author_funders <- function(author) {
  author |>
    str_remove_all("\\s*\\([^()]*\\)") |> # ORCID / ROR comments
    map_chr(\(a) {
      if (is.na(a)) return(NA_character_)
      entries <- str_split_1(a, "(?<=\\]),\\s*") |> # "Name [roles], Name, Suffix [roles]"
        str_match("^(.*?)\\s*\\[([^\\]]*)\\]\\s*$")
      funders <- entries[str_detect(entries[, 3], "\\bfnd\\b") %in% TRUE, 2]
      if (length(funders)) paste(unique(str_squish(funders)), collapse = "; ") else NA_character_
    })
}

# Strong (Depends/Imports/LinkingTo) deps of pkgs on CRAN, base R dropped.
# `...` -> tools::package_dependencies() (recursive = TRUE, reverse = TRUE)
pkg_deps <- function(db, pkgs, ...) {
  pkgs <- intersect(pkgs, db$Package)
  if (!length(pkgs)) return(tibble(package = character(), dep = list()))

  tools::package_dependencies(pkgs, db = as.data.frame(db), which = settings$strong_deps, ...) |>
    enframe(name = "package", value = "dep") |>
    mutate(dep = map(dep, \(d) setdiff(d, base_pkgs())))
}

# What install.packages("tidyverse") brings: the meta-package's direct and recursive
# strong deps (NULL if the db has no tidyverse, so the baseline is unknown)
tidyverse_deps <- function(db) {
  if (!"tidyverse" %in% db$Package) return(NULL)
  list(direct = pkg_deps(db, "tidyverse")$dep[[1]], all = pkg_deps(db, "tidyverse", recursive = TRUE)$dep[[1]])
}

# core = one of the attached 9 (or the meta-package), member = a direct import of
# tidyverse, dep = reached through other deps; NA = outside the tidyverse install
tidyverse_role <- function(pkgs, tv) {
  if (is.null(tv)) return(rep(NA_character_, length(pkgs)))
  case_when(
    pkgs %in% c("tidyverse", settings$tidyverse_core) ~ "core",
    pkgs %in% tv$direct                               ~ "member",
    pkgs %in% tv$all                                  ~ "dep"
  )
}

# Install burden: recursive deps (and how many beyond a tidyverse install), system
# requirements (own + via deps)
install_metrics <- function(db, sysdeps, pkgs, sys_watch) {
  deps     <- pkg_deps(db, pkgs, recursive = TRUE)
  dep_long <- deps |> unnest_longer(dep)
  reqs     <- sysreq_items(db)
  sysdeps  <- sysdeps %||% tibble(package = character(), library = character())
  tv       <- tidyverse_deps(db)

  shown <- reqs |> filter(!noise)
  own   <- shown |> summarise(sysreqs = paste(item, collapse = "; "), .by = package)

  via <- dep_long |>
    inner_join(shown, by = c(dep = "package"), relationship = "many-to-many") |>
    summarise(optional = all(optional), deps = list(sort(unique(dep))), .by = c(package, name)) |>
    mutate(label = paste0(name, if_else(optional, " (optional)", ""), " [", map_chr(deps, label_few), "]")) |>
    summarise(sysreqs_via_deps = paste(label, collapse = "; "), .by = package)

  detected <- bind_rows(deps |> transmute(package, dep = package), dep_long) |>
    inner_join(sysdeps, by = c(dep = "package"), relationship = "many-to-many") |>
    summarise(sysdeps_detected = paste(sort(unique(library)), collapse = "; "), .by = package)

  # sys-deps.yml hits in its own or its deps' requirements: matched on every
  # item's full text (display drops some items and shortens names)
  req_hits <- bind_rows(deps |> transmute(package, dep = package), dep_long) |>
    inner_join(reqs |> transmute(dep = package, hit = watch_hits(item, sys_watch)) |> filter(!is.na(hit)),
               by = "dep", relationship = "many-to-many") |>
    summarise(req_hits = paste(unique(hit), collapse = "; "), .by = package)

  list(
    deps |> transmute(
      package,
      deps_n       = lengths(dep),
      deps_extra_n = if (is.null(tv)) NA_real_ else map_dbl(dep, \(d) sum(!d %in% c("tidyverse", tv$all))),
      tidyverse    = tidyverse_role(package, tv),
      deps         = map_chr(dep, \(d) if (length(d)) paste(sort(d, method = "radix"), collapse = "; ") else NA_character_)
    ),
    own,
    via,
    detected,
    req_hits
  ) |>
    reduce(left_join, by = "package") |>
    mutate(sysreqs_watch = watch_hits(paste(req_hits, sysdeps_detected), sys_watch)) |>
    select(-req_hits)
}

# SystemRequirements of every CRAN package, one row per item
sysreq_items <- function(db) {
  db |>
    filter(!is.na(SystemRequirements)) |>
    transmute(package = Package, item = split_sysreqs(SystemRequirements)) |>
    unnest_longer(item) |>
    mutate(
      name     = item |>
        str_remove("\\s*[(\\[:].*$") |>
        str_remove("(?i)-(dev|devel)$") |> # "libxml2-devel" (an rpm alias) -> "libxml2"
        str_squish() |>
        str_trunc(40), # some are whole sentences
      optional = str_detect(item, "(?i)optional"),
      noise    = name == "" | str_detect(name, settings$sysreq_noise)
    )
}

# Which sys-deps.yml libraries show up (whole word, any case) in each text
watch_hits <- function(text, libs) {
  if (!length(libs)) return(rep(NA_character_, length(text)))
  pattern <- regex(paste0("\\b(", paste(str_escape(libs), collapse = "|"), ")\\b"), ignore_case = TRUE)

  text |>
    str_extract_all(pattern) |>
    map_chr(\(m) {
      m <- m[!is.na(m)]
      if (length(m)) paste(sort(unique(tolower(m))), collapse = "; ") else NA_character_
    })
}

# Direct strong revdeps on CRAN, plus the top ones by r-universe score
revdep_metrics <- function(db, scores, pkgs, complete = TRUE) {
  best <- (scores %||% tibble(package = character(), score = double())) |>
    summarise(score = max_or_na(score), .by = package)

  pkg_deps(db, pkgs, reverse = TRUE) |>
    mutate(revdeps_n = lengths(dep)) |>
    unnest_longer(dep, keep_empty = TRUE) |>
    left_join(best, by = c(dep = "package")) |>
    summarise(
      revdeps_n         = first(revdeps_n),
      revdeps_notable_n = sum(score > settings$revdep_min_score, na.rm = TRUE),
      revdeps_top       = top_revdeps(dep, score),
      .by = package
    ) |>
    mutate(revdeps_notable_n = if (is.null(scores) || !complete) NA_real_ else revdeps_notable_n) # missing scores: unknown, not 0
}

# "targets (21.3), crew (15.2), ..." if >= revdep_min_n revdeps score > revdep_min_score
top_revdeps <- function(pkg, score, s = settings) {
  keep <- which(score > s$revdep_min_score)
  if (length(keep) < s$revdep_min_n) return(NA_character_)

  top <- keep[order(score[keep], decreasing = TRUE)] |> head(s$revdep_top_n)
  paste0(pkg[top], " (", round(score[top]), ")", collapse = ", ")
}
