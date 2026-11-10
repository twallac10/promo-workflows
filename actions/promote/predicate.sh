#!/usr/bin/env bash
# in-toto test-result v0.1 predicate for a behaviour test run, bound to the
# release that was tested (tier's release.yaml by its release id).
# Usage: predicate.sh <tier> <app> <release_id> <revision> <execution> <junit.xml> <run-url>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
junit_cases "$6" | jq -c --arg tier "$1" --arg app "$2" --arg rid "$3" --arg rev "$4" --arg exe "$5" --arg url "$7" '{
  result: (if any(.failed) then "FAILED" else "PASSED" end),
  passedTests: [.[] | select(.failed | not) | .name],
  warnedTests: [],
  failedTests: [.[] | select(.failed) | .name],
  url: $url,
  configuration: [{name: ("tiers/" + $tier + "/release.yaml"), digest: {sha256: ($rid | ltrimstr("sha256:"))},
    annotations: {tier: $tier, app: $app, revision: $rev, execution: $exe}}]
}'
