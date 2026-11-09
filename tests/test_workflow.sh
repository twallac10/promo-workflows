W=$ROOT/.github/workflows/promote.yaml
ACT=$ROOT/actions/promote/action.yml

test_no_payload_interpolation() {
  # client_payload is attacker-controlled: it reaches scripts only as a file.
  for f in "$W" "$ACT"; do
    [ -f "$f" ] || fail "missing $f"
    bad=$(yq '.. | select(has("run")) | .run' "$f" | grep -n 'github\.event\.client_payload' || true)
    [ -z "$bad" ] || fail "$f: run block uses client_payload: $bad"
    bad=$(yq '.. | select(has("run")) | .run' "$f" | grep -n '\${{' || true)
    [ -z "$bad" ] || fail "$f: run block interpolates an expression (use env): $bad"
  done
}

test_workflow_wiring() {
  step_if() { yq ".runs.steps[] | select(.id == \"$1\") | .if" "$ACT"; }
  for id in deploy open-pr revert; do
    step_if $id | grep -q "steps.verify.outputs.status == 'ok'" || fail "$id must require a verified event"
  done
  step_if open-pr | grep -q "steps.parse.outputs.outcome == 'success'" || fail "open-pr on success only"
  step_if open-pr | grep -q "steps.tier.outputs.next != ''" || fail "open-pr needs a next tier"
  step_if revert | grep -q "steps.parse.outputs.outcome == 'failure'" || fail "revert on failure only"
  step_if revert | grep -q "steps.tier.outputs.on_failure == 'rollback'" || fail "revert only in rollback tiers"
  uses=$(yq '.jobs.promote.steps[] | select(.uses | test("actions/promote")) | .uses' "$W")
  [ "$uses" = "twallac10/promo-workflows/actions/promote@v$(cat "$ROOT/VERSION")" ] || fail "action pin $uses != v$(cat "$ROOT/VERSION")"
  [ "$(yq '.jobs.promote.concurrency["cancel-in-progress"]' "$W")" = false ] || fail "concurrency must queue, not cancel"
  yq '.jobs.promote.concurrency.group' "$W" | grep -q 'client_payload.metadata.tier' || fail "concurrency per app and tier"
}
