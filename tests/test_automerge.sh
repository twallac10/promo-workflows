# Every promotion and revert PR merges itself once promotion-gate passes
# (prd: once its environment is approved).

test_upsert_enables_auto_merge() {
  use_gh_stub; d=$(app_repo); new_dev_release "$d" v2
  "$A/open-pr.sh" "$d" dev stg "$(evidence)" >/dev/null
  grep -q '^pr merge promote/stg --auto --squash' "$GH_LOG" || fail "create path: no auto-merge: $(cat "$GH_LOG")"
  new_dev_release "$d" v3; : > "$GH_LOG"
  GH_OPEN_PR=https://github.com/twallac10/promo-kyverno-policies/pull/7 "$A/open-pr.sh" "$d" dev stg "$(evidence)" >/dev/null
  grep -q '^pr merge promote/stg --auto --squash' "$GH_LOG" || fail "edit path: no auto-merge"
  grep -q '^pr edit promote/stg .*--add-label promotion' "$GH_LOG" || fail "edit path must (re)apply the label"
}

test_auto_merge_failure_warns() {
  use_gh_stub; d=$(app_repo); new_dev_release "$d" v2
  out=$(GH_MERGE_FAIL=1 "$A/open-pr.sh" "$d" dev stg "$(evidence)" 2>"$d.err") || fail "auto-merge failure must not fail the run"
  [ "$out" = "pr=https://github.com/twallac10/promo-kyverno-policies/pull/7" ] || fail "stdout must stay key=value for GITHUB_OUTPUT: $out"
  grep -q '^::warning::auto-merge not enabled' "$d.err" || fail "no warning on stderr: $(cat "$d.err")"
}

test_mirror_enables_auto_merge() {
  run=$(yq '.jobs.mirror.steps[] | select(.name == "Open PR for the first tier") | .run' "$ROOT/.github/workflows/mirror.yaml")
  echo "$run" | grep -q 'gh pr merge "$branch" --auto --squash' || fail "mirror PR must enable auto-merge"
  echo "$run" | grep -q '::warning::auto-merge not enabled' || fail "mirror must warn, not fail, when auto-merge is off"
}
