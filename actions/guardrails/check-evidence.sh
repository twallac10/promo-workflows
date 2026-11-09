#!/usr/bin/env bash
# Has the cluster vouched for this? A promotion needs the source tier's latest
# Deployment to be success for the same release id; a revert needs the tier's
# latest Deployment to be failure. Deployments are recorded by the promote
# workflow from Flux events (see promote.yaml).
# Usage: check-evidence.sh <owner/repo> <kind> <tier> <source> <release-id>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
repo=$1 kind=$2 tier=$3 source=$4 release_id=$5
env=$tier; [ "$kind" = promotion ] && env=$source
# task=promote: only the promote workflow's Deployments, not the gate jobs' own.
dep=$(gh api "repos/$repo/deployments?environment=$env&task=promote&per_page=1")
id=$(echo "$dep" | jq -r '.[0].id // empty')
[ -n "$id" ] || fail "no Deployment in $env yet"
got_id=$(echo "$dep" | jq -r '.[0].payload.release_id // empty')
state=$(gh api "repos/$repo/deployments/$id/statuses?per_page=1" | jq -r '.[0].state // empty')
case $kind in
  promotion) [ "$state" = success ] || fail "$env's latest Deployment is '$state', not success"
             [ "$got_id" = "$release_id" ] || fail "$env's latest success is for release $got_id, not $release_id";;
  revert)    [ "$state" = failure ] || fail "$tier's latest Deployment is '$state', not failure: nothing to revert";;
esac
echo "evidence=$env deployment $id $state"
