#!/usr/bin/env bash
# Attach a test run's junit.xml to the chart digest in GHCR as an OCI artifact
# (a referrer of the chart). Assumes `oras login ghcr.io` already happened.
# Usage: attach-junit.sh <app> <digest> <tier> <release_id> <junit.xml>
set -euo pipefail
app=$1 digest=$2 tier=$3 release_id=$4 junit=$5
ref=ghcr.io/twallac10/charts/promo-$app
# Always published as junit.xml, whatever the local file is called.
work=$(mktemp -d); cp "$junit" "$work/junit.xml"; cd "$work"
out=$(oras attach --artifact-type application/vnd.promo.junit.v1+xml \
  --annotation "promo.tier=$tier" --annotation "promo.release-id=$release_id" \
  "$ref@$digest" junit.xml:application/xml)
echo "$out" >&2
echo "junit_ref=$ref@$(echo "$out" | sed -n 's/^Digest: //p')"
