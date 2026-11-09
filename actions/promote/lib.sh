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
