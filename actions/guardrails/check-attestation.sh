#!/usr/bin/env bash
# Promotion evidence: a signed test-result attestation on the chart digest,
# made by the promote workflow (any promo-workflows v* tag, run from the app
# repo's main) for the source tier and this exact release, saying PASSED. Of
# several for that tier and release (re-runs, a fresh task up), the newest
# by transparency-log time decides.
# Usage: check-attestation.sh <owner/repo> <app> <digest> <source-tier> <release-id>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
repo=$1 app=$2 digest=$3 tier=$4 release_id=$5
signer='^https://github\.com/twallac10/promo-workflows/\.github/workflows/promote\.yaml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'
err=$(mktemp)
if ! out=$(gh attestation verify "oci://ghcr.io/twallac10/charts/promo-$app@$digest" -R "$repo" \
    --predicate-type https://in-toto.io/attestation/test-result/v0.1 \
    --cert-identity-regex "$signer" --source-ref refs/heads/main --format json 2>"$err"); then
  fail "no test-result attestation from the promote workflow on promo-$app@$digest: $(tail -1 "$err")"
fi
latest=$(echo "$out" | jq -c --arg t "$tier" --arg h "${release_id#sha256:}" '
  [.[] | .verificationResult | {p: .statement.predicate, ts: ([.verifiedTimestamps[]?.timestamp] | min)}
       | select(.p.configuration[0].annotations.tier == $t and .p.configuration[0].digest.sha256 == $h)]
  | sort_by(.ts) | last // empty')
[ -n "$latest" ] || fail "no test-result attestation for $tier and release $release_id on promo-$app@$digest"
result=$(echo "$latest" | jq -r .p.result)
[ "$result" = PASSED ] || fail "$tier's latest behaviour tests for release $release_id: $result ($(echo "$latest" | jq -r '.p.failedTests | join(", ")'))"
echo "attestation=$tier $result $(echo "$latest" | jq -r .ts)"
