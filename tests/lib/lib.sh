# Shared helpers for tests/test_*.sh. bash 3.2 compatible.
fail() { echo "$*" >&2; exit 1; }
FIX=$ROOT/tests/fixtures
A=$ROOT/actions/promote
# A copy of a success/failure fixture with one jq edit applied; prints its path.
fixture_with() { local f; f=$(mktemp); jq "$2" "$FIX/$1.json" > "$f"; echo "$f"; }
# A throwaway app repo checkout (scripts/release-id.sh + tiers/dev/release.yaml).
app_checkout() { local d; d=$(mktemp -d); cp -R "$FIX/app/." "$d/"; echo "$d"; }
# A git checkout of the fixture app whose origin is a local bare repo; stg
# starts equal to dev. Sets up the gh stub. Prints the checkout path.
app_repo() {
  local root d
  root=$(mktemp -d); d=$root/work
  git init -q --bare -b main "$root/origin.git"
  git clone -q "$root/origin.git" "$d" 2>/dev/null
  cp -R "$FIX/app/." "$d/"
  for t in stg prd; do mkdir -p "$d/tiers/$t"; cp "$d/tiers/dev/release.yaml" "$d/tiers/$t/release.yaml"; done
  for t in dev stg prd; do echo "# tier-only $t" > "$d/tiers/$t/tier.yaml"; done
  git -C "$d" -c user.name=t -c user.email=t@t add -A
  git -C "$d" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$d" push -q origin main
  git -C "$d" config user.name t; git -C "$d" config user.email t@t
  echo "$d"
}
# Point PATH at the gh stub; calls are logged to $GH_LOG.
use_gh_stub() { export PATH="$FIX/bin:$PATH" GH_LOG; GH_LOG=$(mktemp); }
# Commit a change to dev's release.yaml (a new release) on main and push it.
new_dev_release() {
  git -C "$1" checkout -q main
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "'"$2"'"' "$1/tiers/dev/release.yaml"
  "$1/scripts/release-id.sh" --write "$1/tiers/dev/release.yaml"
  git -C "$1" commit -qam "dev: $2"; git -C "$1" push -q origin main
}
# Start a PR branch <name> from main in app checkout <dir>.
pr_branch() { git -C "$1" checkout -q -b "$2" main; }
# Commit everything in <dir> with message <msg>.
commit_all() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
# Canned GitHub Deployments for the gh stub: deployments_fixture <env> <state> <release_id>
deployments_fixture() {
  export GH_FIXTURES=${GH_FIXTURES:-$(mktemp -d)}
  echo "[{\"id\": 9$RANDOM, \"payload\": {\"release_id\": \"$3\"}}]" > "$GH_FIXTURES/deployments-$1.json"
  id=$(jq -r '.[0].id' "$GH_FIXTURES/deployments-$1.json")
  echo "[{\"state\": \"$2\"}]" > "$GH_FIXTURES/statuses-$id.json"
}
evidence() { f=$(mktemp); echo "evidence body" > "$f"; echo "$f"; }
