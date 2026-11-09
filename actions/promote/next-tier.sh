#!/usr/bin/env bash
# Look up a tier in tiers.yaml: the next tier (empty for the last), what to do
# on failure, and whether it needs approval.
# Usage: next-tier.sh <tiers.yaml> <tier>
set -euo pipefail
f=$1; export TIER=$2
yq -e '.tiers[] | select(.name == strenv(TIER))' "$f" >/dev/null 2>&1 || { echo "unknown tier: $TIER" >&2; exit 1; }
i=$(yq '.tiers | to_entries | .[] | select(.value.name == strenv(TIER)) | .key' "$f")
echo "next=$(I=$((i + 1)) yq '.tiers[env(I)].name // ""' "$f")"
echo "on_failure=$(yq ".tiers[$i].onFailure" "$f")"
echo "requires_approval=$(yq ".tiers[$i].requiresApproval" "$f")"
