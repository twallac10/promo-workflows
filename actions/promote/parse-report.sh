#!/usr/bin/env bash
# Parse and validate a Testkube test report (repository_dispatch TestReport/<app>.<app>,
# sent by promo-fleet's promo-report step). Untrusted like any dispatch: every
# field must match a strict pattern. Writes the JUnit to $RUNNER_TEMP/junit.xml
# and decides PASSED/FAILED from its testcases. Prints key=value for $GITHUB_OUTPUT.
# Usage: parse-report.sh <event.json> <repo-name>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
ev=$1 repo=$2
die() { echo "rejected report: $*" >&2; exit 1; }
field() { jq -r "($1) as \$v | if \$v == null then \"\" elif (\$v | type) == \"string\" then \$v else error(\"not a string\") end" "$ev" || die "$1 is not a string"; }
is() { [[ $1 =~ $2 ]]; }

sha='^sha256:[0-9a-f]{64}$'
app=$(field .client_payload.app)
is "$app" '^[a-z][a-z0-9-]{0,40}$' || die "app '$app'"
[ "$repo" = "promo-$app" ] || die "app '$app' is not this repo ($repo)"
[ "$(field .action)" = "TestReport/$app.$app" ] || die "event type"
tier=$(field .client_payload.tier); is "$tier" '^[a-z][a-z0-9-]{0,30}$' || die "tier '$tier'"
digest=$(field .client_payload.digest); is "$digest" "$sha" || die "digest '$digest'"
release_id=$(field .client_payload.release_id); is "$release_id" "$sha" || die "release id '$release_id'"
revision=$(field .client_payload.revision); is "$revision" '^[0-9]{1,6}$' || die "revision '$revision'"
execution=$(field .client_payload.execution); is "$execution" '^[A-Za-z0-9-]{1,64}$' || die "execution '$execution'"

junit=$RUNNER_TEMP/junit.xml
field .client_payload.junit_b64 | base64 -d > "$junit" 2>/dev/null || die "junit_b64 is not base64"
[ -s "$junit" ] || die "empty junit"
[ "$(wc -c < "$junit")" -le 49152 ] || die "junit larger than 48 KiB"
[ "$(yq -p xml -o json '.testsuites.testsuite | type' "$junit" 2>/dev/null)" = '"!!map"' ] || die "junit must be one <testsuite> in <testsuites>"
cases=$(junit_cases "$junit") || die "junit is not valid XML"
[ "$(echo "$cases" | jq length)" -ge 1 ] || die "junit has no testcases"
echo "$cases" | jq -e 'all(.name | type == "string" and test("^[A-Za-z0-9._-]{1,64}$"))' >/dev/null || die "testcase names"
passed=$(echo "$cases" | jq -r '[.[] | select(.failed | not) | .name] | join(",")')
failed=$(echo "$cases" | jq -r '[.[] | select(.failed) | .name] | join(",")')
outcome=success; [ -z "$failed" ] || outcome=failure
upgrade=false; [ "$revision" -gt 1 ] && upgrade=true

echo "kind=report"
echo "outcome=$outcome"
echo "app=$app"
echo "tier=$tier"
echo "digest=$digest"
echo "release_id=$release_id"
echo "revision=$revision"
echo "execution=$execution"
echo "reason=TestReport"
echo "message=behaviour tests: $(echo "$cases" | jq '[.[] | select(.failed | not)] | length') passed, $(echo "$cases" | jq '[.[] | select(.failed)] | length') failed${failed:+ ($failed)}"
echo "upgrade=$upgrade"
echo "passed=$passed"
echo "failed=$failed"
