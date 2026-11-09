#!/usr/bin/env bash
# Parse and validate a Flux repository_dispatch event (client_payload is the
# Flux event). Everything in it is untrusted: each field must match a strict
# pattern before anything uses it. Prints key=value lines for $GITHUB_OUTPUT.
# Usage: parse-event.sh <event.json> <repo-name>
set -euo pipefail
ev=$1 repo=$2
die() { echo "rejected event: $*" >&2; exit 1; }
field() { jq -r "$1 // \"\"" "$ev"; }

sha='^sha256:[0-9a-f]{64}$'
action=$(field .action)
app=$(field .client_payload.metadata.app)
tier=$(field .client_payload.metadata.tier)
digest=$(field '.client_payload.metadata."oci-digest"')
release_id=$(field '.client_payload.metadata."release-id"')
severity=$(field .client_payload.severity)
reason=$(field .client_payload.reason)

echo "$app" | grep -Eq '^[a-z][a-z0-9-]{0,40}$' || die "app '$app'"
[ "$repo" = "promo-$app" ] || die "app '$app' is not this repo ($repo)"
[ "$action" = "HelmRelease/$app.$app" ] || die "event type '$action'"
[ "$(field .client_payload.involvedObject.kind)" = HelmRelease ] || die "involved object kind"
[ "$(field .client_payload.involvedObject.name)" = "$app" ] || die "involved object name"
echo "$tier" | grep -Eq '^[a-z][a-z0-9-]{0,30}$' || die "tier '$tier'"
echo "$digest" | grep -Eq "$sha" || die "digest '$digest'"
echo "$release_id" | grep -Eq "$sha" || die "release id '$release_id'"
echo "$reason" | grep -Eq '^[A-Za-z]{1,40}$' || die "reason '$reason'"
case $severity/$reason in
  info/TestSucceeded) outcome=success;;
  error/TestFailed|error/UpgradeFailed|error/InstallFailed) outcome=failure;;
  *) die "severity '$severity' with reason '$reason' is neither a success nor a failure";;
esac
# One line, at most 1000 characters, for outputs and the Deployment.
message=$(field .client_payload.message | tr '\n\t' '  ' | cut -c1-1000)
# Was this an upgrade (Helm release revision 2+)? Only a failed upgrade is
# rolled back, so only then does Git need a revert PR.
revision=$(echo "$message" | sed -n "s|.*for release $app/$app\.v\([0-9][0-9]*\) .*|\1|p")
case $reason in
  UpgradeFailed) upgrade=true;;
  InstallFailed) upgrade=false;;
  *) if [ "${revision:-1}" -gt 1 ]; then upgrade=true; else upgrade=false; fi;;
esac

echo "outcome=$outcome"
echo "app=$app"
echo "tier=$tier"
echo "digest=$digest"
echo "release_id=$release_id"
echo "reason=$reason"
echo "message=$message"
echo "upgrade=$upgrade"
