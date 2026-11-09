#!/usr/bin/env bash
# Everything is public: no secrets in the PR's commits (gitleaks).
# Usage: scan-secrets.sh <base> <head>
set -euo pipefail
. "$(dirname "$0")/lib.sh"
gitleaks git --no-banner --redact --exit-code 1 --log-opts="$1..$2" . || fail "gitleaks found a possible secret in $1..$2"
