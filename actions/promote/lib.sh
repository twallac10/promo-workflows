# Shared by open-pr.sh and revert-pr.sh. Run inside the app repo checkout.

# Push <branch> (force: one branch per target, always the newest content),
# make sure <label> exists, create the PR or update the open one, then enable
# auto-merge: it merges once promotion-gate passes (prd: once approved).
# Prints pr=<url>.
upsert_pr() {
  local branch=$1 label=$2 title=$3 body=$4 open
  git push -q -f origin "$branch"
  gh label create "$label" --color 0E8A16 --force >/dev/null
  open=$(gh pr list --head "$branch" --state open --json url -q '.[0].url')
  if [ -n "$open" ]; then
    gh pr edit "$branch" --title "$title" --body-file "$body" --add-label "$label" >/dev/null
  else
    open=$(gh pr create --head "$branch" --base main --title "$title" --body-file "$body" --label "$label")
  fi
  enable_auto_merge "$branch"
  echo "pr=$open"
}

# Squash auto-merge. Warns (stderr: stdout feeds $GITHUB_OUTPUT) rather than
# fails when the repo doesn't allow it yet (task gh:envs turns it on).
enable_auto_merge() {
  local err
  err=$(gh pr merge "$1" --auto --squash 2>&1 >/dev/null) || echo "::warning::auto-merge not enabled for $1: $err" >&2
}

# "<app> <chart version>" from a release.yaml, for PR titles.
release_name() {
  echo "$(yq 'select(.kind=="HelmRelease") | .metadata.name' "$1")" \
       "$(yq 'select(.kind=="OCIRepository") | .metadata.annotations."promo.twallac10.dev/chart-version"' "$1")"
}

# The workflow verified the event against the checkout's HEAD. Fail closed
# (print a notice, return 1) if main has since changed tiers/<tier>/: a
# promotion or revert built from the new main would rest on old evidence.
main_unchanged_since() {
  local verified=$1 tier=$2
  git fetch -q origin main
  if ! git diff --quiet "$verified" origin/main -- "tiers/$tier/"; then
    echo "main moved on since the event was verified (tiers/$tier changed); doing nothing" >&2
    return 1
  fi
}

# Close the open PR from <branch>, if any, with <comment>. Prints the closed URL or nothing.
close_open_pr() {
  local branch=$1 comment=$2 open
  open=$(gh pr list --head "$branch" --state open --json url -q '.[0].url')
  [ -z "$open" ] || gh pr close "$branch" --comment "$comment" --delete-branch >/dev/null
  echo "$open"
}
