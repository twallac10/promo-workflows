# Shared helpers for tests/test_*.sh. bash 3.2 compatible.
fail() { echo "$*" >&2; exit 1; }
FIX=$ROOT/tests/fixtures
A=$ROOT/actions/promote
# A copy of a success/failure fixture with one jq edit applied; prints its path.
fixture_with() { local f; f=$(mktemp); jq "$2" "$FIX/$1.json" > "$f"; echo "$f"; }
# A throwaway app repo checkout (scripts/release-id.sh + tiers/dev/release.yaml).
app_checkout() { local d; d=$(mktemp -d); cp -R "$FIX/app/." "$d/"; echo "$d"; }
