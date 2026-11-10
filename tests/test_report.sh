# Test reports from Testkube (TestReport/<app>.<app>): parse, predicate, junit attachment, wiring.
RREPO=promo-kyverno
RID=sha256:1111111111111111111111111111111111111111111111111111111111111111
DIG=sha256:2222222222222222222222222222222222222222222222222222222222222222
rval() { echo "$1" | sed -n "s/^$2=//p"; }

junit_xml() { # <failures>: suite kyverno with deny-dry-run and probe; the first fails if <failures> = 1
  local f='<testcase name="deny-dry-run" time="2"/>'
  [ "$1" = 1 ] && f='<testcase name="deny-dry-run" time="2"><failure message="not denied"/></testcase>'
  printf '<?xml version="1.0"?>\n<testsuites>\n<testsuite name="kyverno" tests="2" failures="%s" errors="0">\n%s\n<testcase name="probe" time="1"/>\n</testsuite>\n</testsuites>\n' "$1" "$f"
}
# A report event file; extra jq edit optional. Prints its path.
report_event() {
  local f; f=$(mktemp)
  jq -n --arg j "$(printf '%s' "$1" | base64 | tr -d '\n')" --arg rid "$RID" --arg dig "$DIG" '{
    action: "TestReport/kyverno.kyverno",
    client_payload: {app: "kyverno", tier: "dev", release_id: $rid, digest: $dig, revision: "3",
      execution: "6af25944648ed96c7826e88d", junit_b64: $j}}' | jq "${2:-.}" > "$f"
  echo "$f"
}
parse_report() { RUNNER_TEMP=$(mktemp -d) "$A/parse-report.sh" "$1" "$RREPO"; }

test_parse_report_pass() {
  out=$(parse_report "$(report_event "$(junit_xml 0)")") || fail "valid report rejected: $out"
  for kv in kind=report outcome=success app=kyverno tier=dev digest=$DIG release_id=$RID revision=3 \
            execution=6af25944648ed96c7826e88d upgrade=true "passed=deny-dry-run,probe" failed=; do
    echo "$out" | grep -qxF "$kv" || fail "want $kv in: $out"
  done
}

test_parse_report_fail() {
  out=$(parse_report "$(report_event "$(junit_xml 1)")") || fail "failing report rejected: $out"
  echo "$out" | grep -qx outcome=failure || fail "outcome: $out"
  echo "$out" | grep -qx failed=deny-dry-run || fail "failed list: $out"
  echo "$out" | grep -qx passed=probe || fail "passed list: $out"
}

test_parse_report_writes_junit() {
  t=$(mktemp -d); RUNNER_TEMP=$t "$A/parse-report.sh" "$(report_event "$(junit_xml 0)")" "$RREPO" >/dev/null || fail "rejected"
  [ "$(cat "$t/junit.xml")" = "$(junit_xml 0)" ] || fail "junit.xml not written verbatim"
}

test_parse_report_rejects_bad_junit() {
  for edit in \
    '.client_payload.junit_b64 = "bm90IHhtbA=="' \
    '.client_payload.junit_b64 = ""' \
    '.client_payload.revision = "3; id"' \
    '.client_payload.execution = "../x"' \
    '.client_payload.tier = "dev\nnext=x"' \
    '.client_payload.release_id = "sha256:abc"' \
    '.action = "TestReport/prometheus.prometheus"'; do
    if out=$(parse_report "$(report_event "$(junit_xml 0)" "$edit")" 2>&1); then fail "accepted: $edit -> $out"; fi
  done
  # no testcases at all
  empty='<?xml version="1.0"?><testsuites><testsuite name="kyverno" tests="0" failures="0" errors="0"></testsuite></testsuites>'
  if parse_report "$(report_event "$empty")" >/dev/null 2>&1; then fail "a report with no testcases accepted"; fi
  # suite claims no failures but a testcase has one: the testcases decide
  lie=$(junit_xml 1 | sed 's/failures="1"/failures="0"/')
  out=$(parse_report "$(report_event "$lie")") || fail "rejected: $out"
  echo "$out" | grep -qx outcome=failure || fail "suite attributes must not override testcases: $out"
  # oversized
  big=$(head -c 60000 /dev/zero | tr '\0' 'x')
  if parse_report "$(report_event "$(junit_xml 0)$big")" >/dev/null 2>&1; then fail "oversized junit accepted"; fi
}

test_predicate_shape() {
  j=$(mktemp); junit_xml 1 > "$j"
  p=$("$A/predicate.sh" dev kyverno "$RID" 3 6af25944648ed96c7826e88d "$j" https://run/1) || fail "predicate.sh failed"
  echo "$p" | jq -e --arg h "${RID#sha256:}" '.result == "FAILED" and .passedTests == ["probe"] and .failedTests == ["deny-dry-run"]
    and .warnedTests == [] and .url == "https://run/1"
    and .configuration == [{"name": "tiers/dev/release.yaml", "digest": {"sha256": $h},
      "annotations": {"tier": "dev", "app": "kyverno", "revision": "3", "execution": "6af25944648ed96c7826e88d"}}]' >/dev/null \
    || fail "predicate: $p"
  junit_xml 0 > "$j"
  [ "$("$A/predicate.sh" dev kyverno "$RID" 3 e "$j" u | jq -r .result)" = PASSED ] || fail "PASSED"
}

test_attach_junit_command() {
  use_gh_stub; j=$(mktemp); junit_xml 0 > "$j"
  out=$(PATH="$FIX/bin:$PATH" ORAS_LOG=$(mktemp) "$A/attach-junit.sh" kyverno "$DIG" dev "$RID" "$j") || fail "attach failed: $out"
  echo "$out" | grep -q '^junit_ref=ghcr.io/twallac10/charts/promo-kyverno@sha256:' || fail "output: $out"
  args=$(cat "$FIX/bin/oras.last")
  for want in attach "--artifact-type application/vnd.promo.junit.v1+xml" "ghcr.io/twallac10/charts/promo-kyverno@$DIG" \
              "junit.xml:application/xml" "--annotation promo.tier=dev" "--annotation promo.release-id=$RID"; do
    echo "$args" | grep -qF -- "$want" || fail "oras args lack '$want': $args"
  done
}

test_report_stale_release_not_attested() {
  ACT=$ROOT/actions/promote/action.yml
  for id in attach-junit attest deploy open-pr close-promotion revert; do
    yq ".runs.steps[] | select(.id == \"$id\") | .if" "$ACT" | grep -q "steps.verify.outputs.status == 'ok'" || fail "$id must require a verified report"
  done
  for id in attach-junit attest; do
    yq ".runs.steps[] | select(.id == \"$id\") | .if" "$ACT" | grep -q "steps.parse.outputs.kind == 'report'" || fail "$id only for test reports"
  done
  [ "$(yq '.runs.steps[] | select(.id == "attest") | .uses' "$ACT")" = "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6" ] || fail "attest pin"
  [ "$(yq '.runs.steps[] | select(.id == "attest") | .with.predicate-type' "$ACT")" = https://in-toto.io/attestation/test-result/v0.1 ] || fail "predicate type"
  [ "$(yq '.runs.steps[] | select(.id == "attest") | .with.push-to-registry' "$ACT")" = true ] || fail "push-to-registry"
}

test_workflow_permissions() {
  W=$ROOT/.github/workflows/promote.yaml
  [ "$(yq -o json -I0 '.permissions' "$W")" = '{"contents":"read","id-token":"write","attestations":"write","packages":"write"}' ] \
    || fail "promote.yaml permissions: $(yq -o json -I0 '.permissions' "$W")"
}
