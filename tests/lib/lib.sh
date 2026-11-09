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
  mkdir -p "$d/tiers/stg"; cp "$d/tiers/dev/release.yaml" "$d/tiers/stg/release.yaml"
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
