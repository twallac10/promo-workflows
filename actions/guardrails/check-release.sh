#!/usr/bin/env bash
# Is the release in the PR the one it claims to be? A promotion must copy the
# source tier's release.yaml from main verbatim; a revert must restore the
# tier's release.yaml from before main's last first-parent change to it.
# Prints release_id= of the PR's file, computed by main's release-id.sh
# (never the PR's: the gate runs no code from the PR).
# Usage: check-release.sh <base> <head> <kind> <tier> <source>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
base=$1 head=$2 kind=$3 tier=$4 source=$5
f=tiers/$tier/release.yaml
tmp=$(mktemp -d)
git show "$head:$f" > "$tmp/pr.yaml" || fail "$f missing in the PR"
case $kind in
  promotion) git show "$base:tiers/$source/release.yaml" > "$tmp/want.yaml"
             what="tiers/$source/release.yaml on main";;
  revert)    last=$(git log -1 --first-parent --format=%H "$base" -- "$f")
             git show "$last^:$f" > "$tmp/want.yaml" 2>/dev/null || fail "$f has no earlier version on main"
             what="$f before its last change on main";;
  *) fail "check-release is for promotion and revert PRs";;
esac
cmp -s "$tmp/pr.yaml" "$tmp/want.yaml" || fail "$f in the PR differs from $what"
git show "$base:scripts/release-id.sh" > "$tmp/release-id.sh"; chmod +x "$tmp/release-id.sh"
echo "release_id=$("$tmp/release-id.sh" "$tmp/pr.yaml")"
