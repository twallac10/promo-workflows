#!/usr/bin/env bash
# The source tier failed: close the open promotion PR to <next>, so an older
# release can't be merged on evidence the latest result contradicts.
# Prints closed=<url or empty>.
# Usage: close-pr.sh <app-repo-dir> <next> <reason>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
dir=$1 next=$2 reason=$3
cd "$dir"
echo "closed=$(close_open_pr "promote/$next" "Closed by the promote workflow: $reason")"
