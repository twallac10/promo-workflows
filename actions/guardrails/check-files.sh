#!/usr/bin/env bash
# Which files may the PR change? A promotion or revert: exactly
# tiers/<tier>/release.yaml. Anything else: no release.yaml outside the first
# tier (the mirror's entry point) - later tiers only change by promotion.
# Usage: check-files.sh <base> <head> <kind> <tier> <first-tier>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
base=$1 head=$2 kind=$3 tier=$4 first=$5
files=$(changed_files "$base" "$head")
if [ "$kind" = other ]; then
  bad=$(echo "$files" | grep -E '^tiers/[^/]+/release\.yaml$' | grep -v "^tiers/$first/release.yaml$" || true)
  [ -z "$bad" ] || fail "$(echo $bad) changed: release.yaml outside the first tier needs a promotion or revert PR"
else
  [ "$files" = "tiers/$tier/release.yaml" ] || fail "a $kind PR may change only tiers/$tier/release.yaml; it changes: $(echo $files)"
fi
