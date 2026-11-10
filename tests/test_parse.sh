REPO=promo-kyverno-policies
out_of() { "$A/parse-event.sh" "$1" "$REPO"; }
val() { echo "$1" | sed -n "s/^$2=//p"; }

test_flux_success_no_longer_accepted() {
  # Promotion is driven by the signed Testkube report now; Flux only reports smoke failures.
  if out=$(out_of "$FIX/success.json" 2>&1); then fail "Flux TestSucceeded accepted: $out"; fi
}

test_parse_failure() {
  out=$(out_of "$FIX/failure.json")
  [ "$(val "$out" outcome)" = failure ] || fail "outcome: $out"
  [ "$(val "$out" reason)" = TestFailed ] || fail "reason: $out"
  [ "$(echo "$out" | grep -c '^message=')" = 1 ] || fail "message must be one line: $out"
  val "$out" message | grep -q 'pod kyverno-policies-test-ready failed' || fail "message: $out"
}

test_parse_truncates_message() {
  f=$(fixture_with failure '.client_payload.message = ("x" * 3000)')
  [ "$(out_of "$f" | sed -n 's/^message=//p' | awk '{print length}')" -le 1000 ] || fail "message not truncated"
}

test_parse_rejects_bad_fields() {
  out_of "$FIX/failure.json" >/dev/null || fail "the valid event must be accepted"
  for edit in \
    '.client_payload.metadata.tier = "dev; curl evil"' \
    '.client_payload.metadata."oci-digest" = "sha256:885316ab"' \
    '.client_payload.metadata."release-id" = "$(id)"' \
    '.action = "HelmRelease/kyverno.kyverno" | .client_payload.involvedObject.name = "kyverno" | .client_payload.metadata.app = "kyverno"' \
    '.client_payload.metadata.app = "prometheus"' \
    '.client_payload.involvedObject.kind = "Kustomization"' \
    '.client_payload.severity = "info"' \
    '.client_payload.metadata.tier = "dev\nnext=x\ntier=../evil"' \
    '.client_payload.metadata."oci-digest" = (.client_payload.metadata."oci-digest" + "\noutcome=success")' \
    '.client_payload.metadata."release-id" = [.client_payload.metadata."release-id"]' \
    '.client_payload.reason = "TestSucceeded\nnext=x"' \
    '.client_payload.reason = "UpgradeSucceeded"'; do
    f=$(fixture_with failure "$edit")
    if out=$(out_of "$f" 2>&1); then fail "accepted: $edit -> $out"; fi
  done
}

test_parse_upgrade_flag() {
  # Revert PRs only make sense after a failed upgrade: a failed first install has nothing to roll back to.
  [ "$(val "$(out_of "$FIX/failure.json")" upgrade)" = true ] || fail "TestFailed on v2 is an upgrade"
  f=$(fixture_with failure '.client_payload.message |= sub("kyverno-policies\\.v2"; "kyverno-policies.v1")')
  [ "$(val "$(out_of "$f")" upgrade)" = false ] || fail "TestFailed on v1 is the first install"
  f=$(fixture_with failure '.client_payload.reason = "InstallFailed" | .client_payload.message = "Helm install failed for release kyverno-policies/kyverno-policies with chart x: boom"')
  [ "$(val "$(out_of "$f")" upgrade)" = false ] || fail "InstallFailed is not an upgrade"
  f=$(fixture_with failure '.client_payload.reason = "UpgradeFailed" | .client_payload.message = "Helm upgrade failed for release kyverno-policies/kyverno-policies with chart x: boom"')
  [ "$(val "$(out_of "$f")" upgrade)" = true ] || fail "UpgradeFailed is an upgrade"
}
