#!/usr/bin/env bash
# Is the event about the release Git says this tier runs? Compares the digest
# and release id with tiers/<tier>/release.yaml in the app repo checkout (main).
# Prints status=ok or status=stale.
# Usage: verify.sh <app-repo-dir> <tier> <digest> <release-id>
set -euo pipefail
dir=$1 tier=$2 digest=$3 release_id=$4
f=$dir/tiers/$tier/release.yaml
want_digest=$(yq 'select(.kind=="OCIRepository") | .spec.ref.digest' "$f")
want_id=$("$dir/scripts/release-id.sh" "$f")
if [ "$digest" = "$want_digest" ] && [ "$release_id" = "$want_id" ]; then
  echo status=ok
else
  echo "stale: event digest $digest release $release_id; main has $want_digest release $want_id" >&2
  echo status=stale
fi
