# Shared by open-pr.sh and revert-pr.sh. Run inside the app repo checkout.

# Push <branch> (force: one branch per target, always the newest content),
# make sure <label> exists, then create the PR or update the open one.
# Prints pr=<url>.
upsert_pr() {
  local branch=$1 label=$2 title=$3 body=$4 open
  git push -q -f origin "$branch"
  gh label create "$label" --color 0E8A16 --force >/dev/null
  open=$(gh pr list --head "$branch" --state open --json url -q '.[0].url')
  if [ -n "$open" ]; then
    gh pr edit "$branch" --title "$title" --body-file "$body" >/dev/null
    echo "pr=$open"
  else
    echo "pr=$(gh pr create --head "$branch" --base main --title "$title" --body-file "$body" --label "$label")"
  fi
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
