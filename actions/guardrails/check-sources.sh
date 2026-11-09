#!/usr/bin/env bash
# Charts come only from our GHCR prefix: no HelmRepository, no OCIRepository
# elsewhere, in any manifest under base/ or tiers/ in the PR - at any depth
# (e.g. inside a List). Fails closed: a file it can't parse fails the check.
# Usage: check-sources.sh <head>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
head=$1
prefix=oci://ghcr.io/twallac10/charts/
tmp=$(mktemp -d)
git ls-tree -r -z --name-only "$head" -- base tiers > "$tmp/files"
while IFS= read -r -d '' f; do
  case $f in *.yaml|*.yml) ;; *) continue;; esac
  git show "$head:$f" > "$tmp/doc" || fail "$f: cannot read"
  yq -o json -I0 '.' "$tmp/doc" > "$tmp/json" 2>/dev/null || fail "$f: cannot parse YAML"
  jq -e '[.. | objects | select(.kind? == "HelmRepository")] | length == 0' "$tmp/json" >/dev/null \
    || fail "$f: HelmRepository is not allowed"
  bad=$(jq -r --arg p "$prefix" '.. | objects | select(.kind? == "OCIRepository") | .spec.url // "" | select(startswith($p) | not)' "$tmp/json")
  [ -z "$bad" ] || fail "$f: OCIRepository $bad is outside $prefix"
done < "$tmp/files"
