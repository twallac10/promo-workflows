G=$ROOT/actions/guardrails
REPO=twallac10/promo-kyverno-policies
val() { echo "$1" | sed -n "s/^$2=//p"; }
# Run a guardrail script inside app checkout <dir>.
in_repo() { local d=$1; shift; (cd "$d" && "$@"); }
set_value() { yq -i '(select(.kind=="HelmRelease") | .spec.values.'"$2"') = "'"$3"'"' "$1"; }
rid_of() { "$1/scripts/release-id.sh" "$2"; }

test_classify() {
  d=$(app_repo); t="$FIX/tiers.yaml"; base=$(git -C "$d" rev-parse main)
  pr_branch "$d" x; set_value "$d/tiers/dev/release.yaml" a 1; set_value "$d/tiers/prd/release.yaml" a 1; commit_all "$d" both
  out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD feature/x "$t")
  [ "$(val "$out" kind)" = other ] && [ "$(val "$out" tier)" = prd ] || fail "dev+prd other PR: $out"
  out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD promote/stg "$t")
  [ "$(echo "$out" | tr '\n' ' ')" = "kind=promotion tier=stg source=dev " ] || fail "promote/stg: $out"
  out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD revert/prd "$t")
  [ "$(val "$out" kind)" = revert ] && [ "$(val "$out" tier)" = prd ] || fail "revert/prd: $out"
  git -C "$d" checkout -q main; pr_branch "$d" y; echo x > "$d/README"; commit_all "$d" readme
  out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD feature/y "$t")
  [ "$(val "$out" kind)" = other ] && [ "$(val "$out" tier)" = "" ] || fail "no-tier PR: $out"
  for ref in promote/dev promote/qa revert/qa; do
    if in_repo "$d" "$G/classify.sh" "$base" HEAD "$ref" "$t" >/dev/null 2>&1; then fail "$ref accepted"; fi
  done
}

test_promotion_sneaks_tier_yaml() {
  d=$(app_repo); base=$(git -C "$d" rev-parse main)
  pr_branch "$d" promote/stg; set_value "$d/tiers/stg/release.yaml" a 1
  echo "validationFailureAction: Enforce" >> "$d/tiers/stg/tier.yaml"; commit_all "$d" sneaky
  if err=$(in_repo "$d" "$G/check-files.sh" "$base" HEAD promotion stg dev 2>&1); then fail "tier.yaml rode along"; fi
  echo "$err" | grep -q 'tiers/stg/tier.yaml' || fail "error must name the file: $err"
  git -C "$d" reset -q --hard HEAD~1; set_value "$d/tiers/stg/release.yaml" a 1; commit_all "$d" clean
  in_repo "$d" "$G/check-files.sh" "$base" HEAD promotion stg dev || fail "clean promotion rejected"
}

test_other_pr_cannot_change_later_release() {
  d=$(app_repo); base=$(git -C "$d" rev-parse main)
  pr_branch "$d" feature/x; set_value "$d/tiers/stg/release.yaml" a 1; commit_all "$d" hand-edit
  if err=$(in_repo "$d" "$G/check-files.sh" "$base" HEAD other stg dev 2>&1); then fail "hand edit of stg release accepted"; fi
  echo "$err" | grep -q 'promotion or revert' || fail "unclear error: $err"
  git -C "$d" reset -q --hard main; set_value "$d/tiers/dev/release.yaml" a 1; echo r: 1 >> "$d/tiers/prd/tier.yaml"; commit_all "$d" ok
  in_repo "$d" "$G/check-files.sh" "$base" HEAD other prd dev || fail "dev release + prd tier.yaml must be allowed"
}

test_promotion_release_must_match_source() {
  d=$(app_repo); new_dev_release "$d" v2; base=$(git -C "$d" rev-parse main)
  pr_branch "$d" promote/stg; set_value "$d/tiers/stg/release.yaml" probe other; commit_all "$d" wrong
  if in_repo "$d" "$G/check-release.sh" "$base" HEAD promotion stg dev >/dev/null 2>&1; then fail "stg != dev accepted"; fi
  git -C "$d" reset -q --hard main; cp "$d/tiers/dev/release.yaml" "$d/tiers/stg/release.yaml"; commit_all "$d" promote
  out=$(in_repo "$d" "$G/check-release.sh" "$base" HEAD promotion stg dev) || fail "matching promotion rejected"
  [ "$(val "$out" release_id)" = "$(rid_of "$d" "$d/tiers/dev/release.yaml")" ] || fail "release_id: $out"
  [ "$(val "$out" digest)" = "$(yq 'select(.kind=="OCIRepository") | .spec.ref.digest' "$d/tiers/dev/release.yaml")" ] || fail "digest: $out"
}

test_revert_release_must_be_previous() {
  d=$(app_repo); prev=$(cat "$d/tiers/stg/release.yaml")
  set_value "$d/tiers/stg/release.yaml" probe bad; "$d/scripts/release-id.sh" --write "$d/tiers/stg/release.yaml"
  commit_all "$d" "stg bad"; git -C "$d" push -q origin main; base=$(git -C "$d" rev-parse main)
  pr_branch "$d" revert/stg; set_value "$d/tiers/stg/release.yaml" probe elsewhere; commit_all "$d" wrong
  if in_repo "$d" "$G/check-release.sh" "$base" HEAD revert stg "" >/dev/null 2>&1; then fail "arbitrary revert accepted"; fi
  git -C "$d" reset -q --hard main; echo "$prev" > "$d/tiers/stg/release.yaml"; commit_all "$d" revert
  in_repo "$d" "$G/check-release.sh" "$base" HEAD revert stg "" >/dev/null || fail "true revert rejected"
}

test_evidence_requires_success_for_same_release() {
  use_gh_stub; export GH_FIXTURES; GH_FIXTURES=$(mktemp -d)
  ev() { "$G/check-evidence.sh" "$REPO" promotion stg dev sha256:aaa >/dev/null 2>&1; }
  if ev; then fail "no Deployment accepted"; fi
  deployments_fixture dev failure sha256:aaa; if ev; then fail "latest failure accepted"; fi
  deployments_fixture dev success sha256:bbb; if ev; then fail "success for another release accepted"; fi
  deployments_fixture dev success sha256:aaa; ev || fail "matching success rejected"
}

test_evidence_revert_requires_failure() {
  use_gh_stub; export GH_FIXTURES; GH_FIXTURES=$(mktemp -d)
  ev() { "$G/check-evidence.sh" "$REPO" revert stg "" sha256:aaa >/dev/null 2>&1; }
  if ev; then fail "revert without a Deployment accepted"; fi
  deployments_fixture stg success sha256:aaa; if ev; then fail "revert after success accepted"; fi
  deployments_fixture stg failure sha256:aaa; ev || fail "revert after failure rejected"
}

test_evidence_uses_base_release_id_script() {
  # A PR that rewrites release-id.sh must not choose the id the gate checks.
  d=$(app_repo); new_dev_release "$d" v2; base=$(git -C "$d" rev-parse main)
  pr_branch "$d" promote/stg; cp "$d/tiers/dev/release.yaml" "$d/tiers/stg/release.yaml"
  printf '#!/bin/sh\necho sha256:%064d\n' 0 > "$d/scripts/release-id.sh"; commit_all "$d" evil
  out=$(in_repo "$d" "$G/check-release.sh" "$base" HEAD promotion stg dev)
  [ "$(val "$out" release_id)" = "$(git -C "$d" show main:scripts/release-id.sh > "$d.rid" && chmod +x "$d.rid" && "$d.rid" "$d/tiers/dev/release.yaml")" ] \
    || fail "gate used the PR's release-id.sh: $out"
}

test_sources_rejects_helmrepository_and_foreign_oci() {
  d=$(app_repo); pr_branch "$d" feature/x
  printf 'apiVersion: source.toolkit.fluxcd.io/v1\nkind: HelmRepository\nmetadata: {name: x}\nspec: {url: https://charts.example}\n' > "$d/tiers/dev/extra.yaml"; commit_all "$d" helmrepo
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "HelmRepository accepted"; fi
  printf 'apiVersion: source.toolkit.fluxcd.io/v1\nkind: OCIRepository\nmetadata: {name: x}\nspec: {url: oci://ghcr.io/evil/charts/x}\n' > "$d/tiers/dev/extra.yaml"; commit_all "$d" foreign
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "foreign OCIRepository accepted"; fi
  git rm -q -C "$d" tiers/dev/extra.yaml 2>/dev/null || git -C "$d" rm -q tiers/dev/extra.yaml; commit_all "$d" clean
  in_repo "$d" "$G/check-sources.sh" HEAD || fail "clean tree rejected"
}

test_scan_secrets_finds_planted_token() {
  command -v gitleaks >/dev/null || { echo "skip (gitleaks not installed; CI installs it)"; return 0; }
  d=$(app_repo); base=$(git -C "$d" rev-parse main); pr_branch "$d" feature/x
  echo "token: ghp_$(printf 'aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5')" > "$d/tiers/dev/leak.yaml"; commit_all "$d" leak
  if in_repo "$d" "$G/scan-secrets.sh" "$base" HEAD >/dev/null 2>&1; then fail "planted token not found"; fi
  git -C "$d" reset -q --hard main; echo "# fine" >> "$d/tiers/dev/tier.yaml"; commit_all "$d" clean
  in_repo "$d" "$G/scan-secrets.sh" "$base" HEAD >/dev/null || fail "clean PR flagged"
}

test_guardrails_action_wiring() {
  a="$G/action.yml"; [ -f "$a" ] || fail "missing $a"
  bad=$(yq '.. | select(has("run")) | .run' "$a" | grep -n '\${{' || true)
  [ -z "$bad" ] || fail "run block interpolates an expression: $bad"
  yq '.runs.steps[] | select(.id == "check-release") | .if' "$a" | grep -q "steps.classify.outputs.kind != 'other'" || fail "check-release for promotion/revert only"
  yq '.runs.steps[] | select(.id == "check-attestation") | .if' "$a" | grep -q "steps.classify.outputs.kind == 'promotion'" || fail "promotions need a verified attestation"
  yq '.runs.steps[] | select(.id == "check-evidence") | .if' "$a" | grep -q "steps.classify.outputs.kind == 'revert'" || fail "check-evidence (Deployment) only for reverts now"
  [ "$(yq '.outputs.environment.value' "$a")" = '${{ steps.classify.outputs.tier }}' ] || fail "environment output"
  [ "$(yq '.inputs.fleet-repo.default' "$a")" = twallac10/promo-fleet ] || fail "fleet-repo default"
}

test_sources_fails_closed() {
  hr='{apiVersion: source.toolkit.fluxcd.io/v1, kind: HelmRepository, metadata: {name: x}, spec: {url: "https://charts.example"}}'
  d=$(app_repo); pr_branch "$d" feature/x
  echo "$hr" > "$d/tiers/dev/a b.yaml"; commit_all "$d" "space in name"
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "HelmRepository in a file name with a space accepted"; fi
  git -C "$d" reset -q --hard main
  printf 'apiVersion: v1\nkind: List\nitems:\n  - %s\n' "$hr" > "$d/tiers/dev/list.yaml"; commit_all "$d" "nested"
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "HelmRepository nested in a List accepted"; fi
  git -C "$d" reset -q --hard main
  printf 'kind: [unclosed\n' > "$d/tiers/dev/broken.yaml"; commit_all "$d" "broken"
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "unparseable YAML skipped"; fi
}

test_classify_shared_paths_need_last_tier() {
  # base/ deploys to every tier at once; .github/ and scripts/ change the gate and
  # promotion machinery: such PRs need the last tier's approval.
  t="$FIX/tiers.yaml"
  for p in base/helmrelease.yaml .github/workflows/gate.yaml scripts/release-id.sh; do
    d=$(app_repo); base=$(git -C "$d" rev-parse main); pr_branch "$d" feature/x
    mkdir -p "$d/$(dirname "$p")"; echo "# change" >> "$d/$p"; commit_all "$d" "touch $p"
    out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD feature/x "$t")
    [ "$(val "$out" kind)" = other ] && [ "$(val "$out" tier)" = prd ] || fail "$p: want other/prd, got: $out"
  done
}

test_sources_checks_every_document() {
  # jq -e's exit status reflects only the last document: a clean one after a
  # HelmRepository must not hide it.
  d=$(app_repo); pr_branch "$d" feature/x
  printf 'apiVersion: source.toolkit.fluxcd.io/v1\nkind: HelmRepository\nmetadata: {name: x}\nspec: {url: "https://charts.example"}\n---\napiVersion: v1\nkind: ConfigMap\nmetadata: {name: y}\n' > "$d/tiers/dev/multi.yaml"
  commit_all "$d" multi
  if in_repo "$d" "$G/check-sources.sh" HEAD >/dev/null 2>&1; then fail "HelmRepository in the first of two documents accepted"; fi
}

test_renames_count_both_paths() {
  # git diff detects renames and lists only the new path; moving a prd/base/.github
  # file into tiers/dev/ must still count as touching where it came from.
  t="$FIX/tiers.yaml"
  for src in tiers/prd/release.yaml base/helmrelease.yaml .github/workflows/gate.yaml; do
    d=$(app_repo); mkdir -p "$d/$(dirname "$src")"
    if [ ! -f "$d/$src" ]; then printf 'name: x\non: push\njobs: {}\n' > "$d/$src"; commit_all "$d" "add $src"; git -C "$d" push -q origin main; fi
    base=$(git -C "$d" rev-parse main)
    pr_branch "$d" feature/move; git -C "$d" mv "$src" tiers/dev/moved.yaml; commit_all "$d" "move $src"
    out=$(in_repo "$d" "$G/classify.sh" "$base" HEAD feature/move "$t")
    [ "$(val "$out" tier)" = prd ] || fail "moving $src into tiers/dev must be gated by prd, got: $out"
  done
  d=$(app_repo); base=$(git -C "$d" rev-parse main); pr_branch "$d" feature/move
  git -C "$d" mv tiers/prd/release.yaml tiers/dev/old.yaml; commit_all "$d" "move prd release"
  if in_repo "$d" "$G/check-files.sh" "$base" HEAD other prd dev >/dev/null 2>&1; then fail "moving prd's release.yaml away accepted"; fi
}

# Canned `gh attestation verify --format json` output: att <tier> <release hex> <result> <timestamp> ...
attestations() {
  local f; f=$(mktemp); local items=()
  while [ $# -gt 0 ]; do
    items+=("$(jq -n --arg t "$1" --arg h "$2" --arg r "$3" --arg ts "$4" '{verificationResult: {
      statement: {predicateType: "https://in-toto.io/attestation/test-result/v0.1",
        predicate: {result: $r, configuration: [{name: ("tiers/" + $t + "/release.yaml"), digest: {sha256: $h}, annotations: {tier: $t}}]}},
      verifiedTimestamps: [{type: "Tlog", timestamp: $ts}]}}')"); shift 4
  done
  printf '%s\n' "${items[@]}" | jq -s . > "$f"; echo "$f"
}
H1=1111111111111111111111111111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222222222222222222222222222
D=sha256:3333333333333333333333333333333333333333333333333333333333333333
check_att() { "$G/check-attestation.sh" twallac10/promo-kyverno kyverno "$D" dev "sha256:$H1"; }

test_attestation_requires_passed_for_tier_and_release() {
  use_gh_stub
  GH_ATTESTATIONS=$(attestations dev $H1 PASSED 2026-11-10T10:00:00Z) check_att >/dev/null || fail "matching PASSED rejected"
  if GH_ATTESTATIONS=$(attestations dev $H1 FAILED 2026-11-10T10:00:00Z) check_att >/dev/null 2>&1; then fail "FAILED accepted"; fi
  if GH_ATTESTATIONS=$(attestations stg $H1 PASSED 2026-11-10T10:00:00Z) check_att >/dev/null 2>&1; then fail "another tier's PASSED accepted"; fi
  if GH_ATTESTATIONS=$(attestations dev $H2 PASSED 2026-11-10T10:00:00Z) check_att >/dev/null 2>&1; then fail "another release's PASSED accepted"; fi
}

test_attestation_picks_latest_for_tier_and_release() {
  use_gh_stub
  if GH_ATTESTATIONS=$(attestations dev $H1 PASSED 2026-11-10T10:00:00Z dev $H1 FAILED 2026-11-10T11:00:00Z) check_att >/dev/null 2>&1; then
    fail "older PASSED must not win over a newer FAILED"; fi
  GH_ATTESTATIONS=$(attestations dev $H1 FAILED 2026-11-10T10:00:00Z dev $H1 PASSED 2026-11-10T11:00:00Z stg $H1 FAILED 2026-11-10T12:00:00Z) check_att >/dev/null \
    || fail "newer PASSED (a retest) must win; other tiers don't count"
}

test_attestation_verify_enforces_signer() {
  use_gh_stub; GH_ATTESTATIONS=$(attestations dev $H1 PASSED 2026-11-10T10:00:00Z) check_att >/dev/null
  a=$(grep '^attestation verify' "$GH_LOG")
  for want in "oci://ghcr.io/twallac10/charts/promo-kyverno@$D" "-R twallac10/promo-kyverno" \
      "--predicate-type https://in-toto.io/attestation/test-result/v0.1" "--source-ref refs/heads/main" "--format json" \
      '--cert-identity-regex ^https://github\.com/twallac10/promo-workflows/\.github/workflows/promote\.yaml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'; do
    echo "$a" | grep -qF -- "$want" || fail "verify args lack '$want': $a"
  done
}

test_attestation_none() {
  use_gh_stub
  if err=$(GH_ATTEST_EXIT=1 check_att 2>&1); then fail "no verifiable attestation accepted"; fi
  echo "$err" | grep -q 'guardrail:' || fail "no reason given: $err"
}
