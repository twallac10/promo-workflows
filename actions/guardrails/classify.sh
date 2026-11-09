#!/usr/bin/env bash
# What kind of PR is this, and which tier's environment gates it? By branch
# name (labels can be edited by anyone with triage access):
#   promote/<tier>  promotion into <tier> (from the previous tier)
#   revert/<tier>   revert of <tier>'s release
#   anything else   other: gated by the last tier (in tiers.yaml order) it touches, or none
# Prints kind=, tier=, and source= for promotions.
# Usage: classify.sh <base> <head> <head-ref> <tiers.yaml>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
base=$1 head=$2 ref=$3 tiers=$4
names=$(yq '.tiers[].name' "$tiers")
index_of() { echo "$names" | grep -nx -- "$1" | cut -d: -f1; }
case $ref in
  promote/*|revert/*)
    kind=promotion; [ "${ref%%/*}" = revert ] && kind=revert
    tier=${ref#*/}
    i=$(index_of "$tier" || true)
    [ -n "$i" ] || fail "$ref: '$tier' is not a tier in tiers.yaml"
    if [ $kind = promotion ]; then
      [ "$i" -gt 1 ] || fail "$ref: nothing promotes into the first tier (the mirror PR is its entry point)"
      echo "kind=promotion"; echo "tier=$tier"; echo "source=$(echo "$names" | sed -n "$((i - 1))p")"
    else
      echo "kind=revert"; echo "tier=$tier"
    fi;;
  *)
    tier=
    for t in $names; do changed_files "$base" "$head" | grep -q "^tiers/$t/" && tier=$t; done
    echo "kind=other"; echo "tier=$tier";;
esac
