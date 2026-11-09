#!/usr/bin/env bash
# Charts come only from our GHCR prefix: no HelmRepository, no OCIRepository
# elsewhere, in any manifest under base/ or tiers/ in the PR.
# Usage: check-sources.sh <head>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
head=$1
prefix=oci://ghcr.io/twallac10/charts/
for f in $(git ls-tree -r --name-only "$head" -- base tiers | grep -E '\.ya?ml$'); do
  docs=$(git show "$head:$f" | yq -o json -I0 '.' 2>/dev/null) || continue
  echo "$docs" | jq -e 'select(.kind == "HelmRepository")' >/dev/null 2>&1 && fail "$f: HelmRepository is not allowed"
  bad=$(echo "$docs" | jq -r --arg p "$prefix" 'select(.kind == "OCIRepository") | .spec.url // "" | select(startswith($p) | not)')
  [ -z "$bad" ] || fail "$f: OCIRepository $bad is outside $prefix"
done
