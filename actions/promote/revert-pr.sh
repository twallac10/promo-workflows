#!/usr/bin/env bash
# Revert PR after a failed upgrade in a rollback tier: Flux rolled the cluster
# back, so Git must follow. Restores tiers/<tier>/release.yaml as it was before
# the last change on main's first-parent history, on branch revert/<tier> -
# but only if that last change to tiers/<tier>/ was to release.yaml (a failure
# after a tier.yaml change isn't the release's fault) and main hasn't moved
# since the event was verified. Prints pr=<url or empty>.
# Usage: revert-pr.sh <app-repo-dir> <tier> <evidence-markdown-file>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
dir=$1 tier=$2 evidence=$3
cd "$dir"
verified=$(git rev-parse HEAD)
main_unchanged_since "$verified" "$tier" || { echo "pr="; exit 0; }
f=tiers/$tier/release.yaml
last=$(git log -1 --first-parent --format=%H "$verified" -- "tiers/$tier/")
if ! git cat-file -e "$last^:$f" 2>/dev/null; then
  echo "no earlier version of $f to revert to; leaving it for a human" >&2
  echo "pr="
  exit 0
fi
if git diff --quiet "$last^" "$last" -- "$f"; then
  echo "the last change to tiers/$tier was not release.yaml (e.g. tier.yaml); leaving it for a human" >&2
  echo "pr="
  exit 0
fi
branch=revert/$tier
git checkout -q -B "$branch" origin/main
git show "$last^:$f" > "$f"
title="revert($tier): $(release_name "$f")"
git commit -q -am "$title"
upsert_pr "$branch" revert "$title" "$evidence"
