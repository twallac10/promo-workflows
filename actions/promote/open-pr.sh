#!/usr/bin/env bash
# Promotion PR: copy tiers/<tier>/release.yaml to tiers/<next>/release.yaml on
# branch promote/<next> (from main), and nothing else. Only from the verified
# checkout (HEAD): if main changed tiers/<tier>/ since, nothing happens. When
# <next> already has this release, an open promotion PR is obsolete and closed.
# Prints pr=<url or empty>.
# Usage: open-pr.sh <app-repo-dir> <tier> <next> <evidence-markdown-file>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
dir=$1 tier=$2 next=$3 evidence=$4
cd "$dir"
verified=$(git rev-parse HEAD)
main_unchanged_since "$verified" "$tier" || { echo "pr="; exit 0; }
branch=promote/$next
git checkout -q -B "$branch" origin/main
cp "tiers/$tier/release.yaml" "tiers/$next/release.yaml"
if git diff --quiet; then
  echo "$next already has this release" >&2
  close_open_pr "$branch" "Closed by the promote workflow: $next already runs the release from $tier." >/dev/null
  echo "pr="
  exit 0
fi
title="promote($next): $(release_name "tiers/$next/release.yaml")"
git commit -q -am "$title"
upsert_pr "$branch" promotion "$title" "$evidence"
