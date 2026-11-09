test_open_pr_creates_branch_and_pr() {
  use_gh_stub; d=$(app_repo); new_dev_release "$d" v2
  out=$("$A/open-pr.sh" "$d" dev stg "$(evidence)")
  [ "$out" = "pr=https://github.com/twallac10/promo-kyverno-policies/pull/7" ] || fail "output: $out"
  changed=$(git -C "$d" diff --name-only origin/main origin/promote/stg)
  [ "$changed" = tiers/stg/release.yaml ] || fail "promotion diff touches: $changed"
  git -C "$d" diff --quiet origin/main:tiers/dev/release.yaml origin/promote/stg:tiers/stg/release.yaml || fail "stg != dev"
  grep -q '^pr create .*--head promote/stg' "$GH_LOG" || fail "no pr create: $(cat "$GH_LOG")"
  grep -q '^pr create .*--label promotion' "$GH_LOG" || fail "PR not labelled promotion"
  grep -q '^label create promotion' "$GH_LOG" || fail "label not ensured"
}

test_open_pr_idempotent() {
  use_gh_stub; d=$(app_repo); new_dev_release "$d" v2
  "$A/open-pr.sh" "$d" dev stg "$(evidence)" >/dev/null
  new_dev_release "$d" v3
  out=$(GH_OPEN_PR=https://github.com/twallac10/promo-kyverno-policies/pull/7 "$A/open-pr.sh" "$d" dev stg "$(evidence)")
  [ "$out" = "pr=https://github.com/twallac10/promo-kyverno-policies/pull/7" ] || fail "output: $out"
  [ "$(grep -c '^pr create' "$GH_LOG")" = 1 ] || fail "second PR created: $(cat "$GH_LOG")"
  grep -q '^pr edit promote/stg' "$GH_LOG" || fail "open PR not updated"
  [ "$(git -C "$d" show origin/promote/stg:tiers/stg/release.yaml | yq 'select(.kind=="HelmRelease") | .spec.values.probe')" = v3 ] \
    || fail "branch not moved to the newest release"
}

test_open_pr_noop_when_equal() {
  use_gh_stub; d=$(app_repo)
  out=$("$A/open-pr.sh" "$d" dev stg "$(evidence)")
  [ "$out" = "pr=" ] || fail "output: $out"
  ! grep -qE '^pr (create|edit|close)' "$GH_LOG" || fail "PR created, edited or closed: $(cat "$GH_LOG")"
  ! git -C "$d" ls-remote --exit-code origin promote/stg >/dev/null || fail "branch pushed"
}

test_revert_only_in_rollback_tiers() {
  use_gh_stub; d=$(app_repo)
  # One-commit history: nothing to revert to.
  out=$("$A/revert-pr.sh" "$d" stg "$(evidence)" 2>&1)
  echo "$out" | grep -q '^pr=$' || fail "single commit: $out"
  echo "$out" | grep -qi 'no earlier' || fail "no notice: $out"
  ! grep -q '^pr ' "$GH_LOG" || fail "gh pr called with nothing to revert"
  # stg moves to a new release; revert brings back the previous one.
  before=$(cat "$d/tiers/stg/release.yaml")
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "bad"' "$d/tiers/stg/release.yaml"
  git -C "$d" commit -qam "stg: bad"; git -C "$d" push -q origin main
  out=$("$A/revert-pr.sh" "$d" stg "$(evidence)")
  [ "$out" = "pr=https://github.com/twallac10/promo-kyverno-policies/pull/7" ] || fail "output: $out"
  [ "$(git -C "$d" diff --name-only origin/main origin/revert/stg)" = tiers/stg/release.yaml ] || fail "revert touches more"
  [ "$(git -C "$d" show origin/revert/stg:tiers/stg/release.yaml)" = "$before" ] || fail "not the previous release"
  grep -q '^pr create .*--label revert' "$GH_LOG" || fail "revert PR not labelled revert"
}

test_deploy_truncates_description() {
  use_gh_stub
  long=$(printf 'x%.0s' $(seq 1 300))
  out=$("$A/deploy.sh" twallac10/promo-kyverno-policies dev failure abc123 sha256:d sha256:r "$long" https://run)
  echo "$out" | grep -q '^deployment_url=https://github.com/twallac10/promo-kyverno-policies/deployments/dev$' || fail "output: $out"
  dep=$(cat "$GH_LOG".body.1); st=$(cat "$GH_LOG".body.2)
  echo "$dep" | jq -e '.ref == "abc123" and .environment == "dev" and .auto_merge == false and .required_contexts == []
    and .task == "promote" and .payload == {"digest": "sha256:d", "release_id": "sha256:r"}' >/dev/null || fail "deployment: $dep"
  grep -q '^api -X POST repos/twallac10/promo-kyverno-policies/deployments/42/statuses' "$GH_LOG" || fail "status not on deployment 42"
  echo "$st" | jq -e '.state == "failure" and (.description | length) == 140 and .log_url == "https://run"' >/dev/null || fail "status: $st"
}

test_open_pr_refuses_moved_main() {
  # Evidence is for the verified checkout; if main moved on, its release is untested.
  use_gh_stub; d=$(app_repo); new_dev_release "$d" v2; new_dev_release "$d" v3
  git -C "$d" reset -q --hard HEAD~1 # verified checkout = v2; origin/main = v3
  out=$("$A/open-pr.sh" "$d" dev stg "$(evidence)" 2>"$d.err")
  [ "$out" = "pr=" ] || fail "output: $out"
  grep -qi 'moved' "$d.err" || fail "no notice: $(cat "$d.err")"
  ! grep -q '^pr ' "$GH_LOG" || fail "gh pr called"
  ! git -C "$d" ls-remote --exit-code origin promote/stg >/dev/null || fail "branch pushed"
}

test_open_pr_noop_closes_stale_pr() {
  # stg already has dev's release: an open promotion PR (an older release) is obsolete.
  use_gh_stub; d=$(app_repo)
  out=$(GH_OPEN_PR=https://github.com/twallac10/promo-kyverno-policies/pull/7 "$A/open-pr.sh" "$d" dev stg "$(evidence)")
  [ "$out" = "pr=" ] || fail "output: $out"
  grep -q '^pr close promote/stg' "$GH_LOG" || fail "stale promotion PR not closed: $(cat "$GH_LOG")"
}

test_close_pr_on_failure() {
  use_gh_stub; d=$(app_repo)
  out=$(GH_OPEN_PR=https://github.com/twallac10/promo-kyverno-policies/pull/7 "$A/close-pr.sh" "$d" stg "dev reported TestFailed")
  [ "$out" = "closed=https://github.com/twallac10/promo-kyverno-policies/pull/7" ] || fail "output: $out"
  grep -q '^pr close promote/stg' "$GH_LOG" || fail "not closed"
  use_gh_stub
  [ "$("$A/close-pr.sh" "$d" stg "x")" = "closed=" ] || fail "no open PR must be a no-op"
  ! grep -q '^pr close' "$GH_LOG" || fail "closed with nothing open"
}

stg_release_commit() {
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "'"$2"'"' "$1/tiers/stg/release.yaml"
  git -C "$1" commit -qam "stg: $2"; git -C "$1" push -q origin main
}
stg_release_other() {
  yq -i '(select(.kind=="OCIRepository") | .metadata.annotations."promo.twallac10.dev/chart-version") = "'"$2"'"' "$1/tiers/stg/release.yaml"
  git -C "$1" commit -qam "stg: other $2"
}

test_revert_refuses_moved_main() {
  use_gh_stub; d=$(app_repo); stg_release_commit "$d" b; stg_release_commit "$d" c
  git -C "$d" reset -q --hard HEAD~1 # verified = b; main moved to c
  out=$("$A/revert-pr.sh" "$d" stg "$(evidence)" 2>/dev/null)
  [ "$out" = "pr=" ] || fail "reverted on a moved main: $out"
  ! grep -q '^pr ' "$GH_LOG" || fail "gh pr called"
}

test_revert_skips_when_last_change_not_release() {
  # A failure after a tier.yaml change isn't the chart's fault: don't roll the chart back.
  use_gh_stub; d=$(app_repo); stg_release_commit "$d" b
  echo "replicas: 2" > "$d/tiers/stg/tier.yaml"
  git -C "$d" add -A; git -C "$d" commit -qm "stg: tier.yaml"; git -C "$d" push -q origin main
  out=$("$A/revert-pr.sh" "$d" stg "$(evidence)" 2>"$d.err")
  [ "$out" = "pr=" ] || fail "reverted the chart after a tier.yaml change: $out"
  grep -qi 'tier.yaml\|not release.yaml' "$d.err" || fail "no notice: $(cat "$d.err")"
}

test_revert_follows_first_parent() {
  # Merged PR: the commit that changed release.yaml on a branch is older than main's merge.
  use_gh_stub; d=$(app_repo); stg_release_commit "$d" b
  git -C "$d" checkout -q -b feature HEAD
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "c"' "$d/tiers/stg/release.yaml"
  git -C "$d" commit -qam "stg: c (branch)"
  git -C "$d" checkout -q main
  stg_release_other "$d" b2 # main changes the release too, after the branch point
  git -C "$d" merge -q --no-ff -m "merge feature" feature; git -C "$d" push -q origin main
  out=$("$A/revert-pr.sh" "$d" stg "$(evidence)")
  [ "$(git -C "$d" show origin/revert/stg:tiers/stg/release.yaml | yq 'select(.kind=="OCIRepository") | .metadata.annotations."promo.twallac10.dev/chart-version"')" = b2 ] \
    || fail "revert must restore main's release just before the merge (chart-version b2): $out"
}
