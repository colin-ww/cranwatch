#!/usr/bin/env bash
# Top 1000 GitHub repos with language:R, by stars (the search API stops at 1000). Needs an authenticated gh.
# Run from the repo root: explore/not-on-cran/gh_top.sh
set -euo pipefail
out="explore/not-on-cran/out/gh_top_r.tsv"
mkdir -p "$(dirname "$out")"
: > "$out"
for p in $(seq 1 10); do
  gh api -X GET search/repositories -f q='language:R' -f sort=stars -f per_page=100 -f page="$p" \
    --jq '.items[] | [.full_name, .name, .stargazers_count, .archived, (.pushed_at|.[0:10]), ((.description // "")|gsub("[\t\n]";" ")|.[0:80])] | @tsv' >> "$out"
  sleep 8 # search API: stay well under its per-minute limit
done
