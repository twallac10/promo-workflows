REPO=promo-kyverno-policies
out_of() { "$A/parse-event.sh" "$1" "$REPO"; }
val() { echo "$1" | sed -n "s/^$2=//p"; }

test_parse_success() {
  out=$(out_of "$FIX/success.json")
  [ "$(val "$out" outcome)" = success ] || fail "outcome: $out"
  [ "$(val "$out" app)" = kyverno-policies ] || fail "app: $out"
  [ "$(val "$out" tier)" = dev ] || fail "tier: $out"
  [ "$(val "$out" digest)" = sha256:885316ab9f6c6e0ffa78a44882b1d4126dc5b5ace08d0311ba4a8db39a8bc35c ] || fail "digest: $out"
  [ "$(val "$out" release_id)" = "$(jq -r '.client_payload.metadata."release-id"' "$FIX/success.json")" ] || fail "release_id: $out"
  [ "$(val "$out" reason)" = TestSucceeded ] || fail "reason: $out"
  val "$out" message | grep -q '^Helm test succeeded for release' || fail "message: $out"
}

test_parse_failure() {
  out=$(out_of "$FIX/failure.json")
  [ "$(val "$out" outcome)" = failure ] || fail "outcome: $out"
  [ "$(val "$out" reason)" = TestFailed ] || fail "reason: $out"
  [ "$(echo "$out" | grep -c '^message=')" = 1 ] || fail "message must be one line: $out"
  val "$out" message | grep -q 'pod kyverno-policies-test-ready failed' || fail "message: $out"
}

test_parse_truncates_message() {
  f=$(fixture_with success '.client_payload.message = ("x" * 3000)')
  [ "$(out_of "$f" | sed -n 's/^message=//p' | awk '{print length}')" -le 1000 ] || fail "message not truncated"
}

test_parse_rejects_bad_fields() {
  out_of "$FIX/success.json" >/dev/null || fail "the valid event must be accepted"
  for edit in \
    '.client_payload.metadata.tier = "dev; curl evil"' \
    '.client_payload.metadata."oci-digest" = "sha256:885316ab"' \
    '.client_payload.metadata."release-id" = "$(id)"' \
    '.action = "HelmRelease/kyverno.kyverno" | .client_payload.involvedObject.name = "kyverno" | .client_payload.metadata.app = "kyverno"' \
    '.client_payload.metadata.app = "prometheus"' \
    '.client_payload.involvedObject.kind = "Kustomization"' \
    '.client_payload.severity = "error"' \
    '.client_payload.reason = "UpgradeSucceeded"'; do
    f=$(fixture_with success "$edit")
    if out=$(out_of "$f" 2>&1); then fail "accepted: $edit -> $out"; fi
  done
}
