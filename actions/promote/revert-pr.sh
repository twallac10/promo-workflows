#!/usr/bin/env bash
# Revert PR after a failure in a rollback tier: Flux rolled the cluster back,
# so Git must follow. Restores tiers/<tier>/release.yaml as it was before the
# last commit that changed it, on branch revert/<tier>. Prints pr=<url or empty>.
# Usage: revert-pr.sh <app-repo-dir> <tier> <evidence-markdown-file>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
dir=$1 tier=$2 evidence=$3
cd "$dir"
git fetch -q origin main
f=tiers/$tier/release.yaml
last=$(git log -1 --format=%H origin/main -- "$f")
if ! git cat-file -e "$last^:$f" 2>/dev/null; then
  echo "no earlier version of $f to revert to; leaving it for a human" >&2
  echo "pr="
  exit 0
fi
branch=revert/$tier
git checkout -q -B "$branch" origin/main
git show "$last^:$f" > "$f"
if git diff --quiet; then
  echo "$f already matches its previous version" >&2
  echo "pr="
  exit 0
fi
title="revert($tier): $(release_name "$f")"
git commit -q -am "$title"
upsert_pr "$branch" revert "$title" "$evidence"
