#!/usr/bin/env bash
# Record a GitHub Deployment for <tier> with one status: the per-app, per-tier
# evidence ledger. task "promote" tells these apart from the Deployments GitHub
# records for gate jobs that run in an environment. Prints deployment_id= and deployment_url=.
# Usage: deploy.sh <owner/repo> <tier> <success|failure> <sha> <digest> <release-id> <description> <log-url>
set -euo pipefail
repo=$1 tier=$2 state=$3 sha=$4 digest=$5 release_id=$6 desc=$7 log_url=$8
desc=$(printf '%s' "$desc" | cut -c1-140) # GitHub's limit
id=$(jq -n --arg ref "$sha" --arg env "$tier" --arg d "$digest" --arg r "$release_id" --arg desc "$desc" \
  '{ref: $ref, environment: $env, task: "promote", auto_merge: false, required_contexts: [], description: $desc,
    payload: {digest: $d, release_id: $r}}' |
  gh api -X POST "repos/$repo/deployments" --input - | jq -r .id)
jq -n --arg s "$state" --arg desc "$desc" --arg u "$log_url" --arg env "$tier" \
  '{state: $s, description: $desc, log_url: $u, environment: $env}' |
  gh api -X POST "repos/$repo/deployments/$id/statuses" --input - >/dev/null
echo "deployment_id=$id"
echo "deployment_url=https://github.com/$repo/deployments/$tier"
