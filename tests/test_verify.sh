test_next_tier() {
  t="$FIX/tiers.yaml"
  [ "$("$A/next-tier.sh" "$t" dev | tr '\n' ' ')" = "next=stg on_failure=hold requires_approval=false " ] || fail "dev"
  [ "$("$A/next-tier.sh" "$t" stg | tr '\n' ' ')" = "next=prd on_failure=rollback requires_approval=false " ] || fail "stg"
  [ "$("$A/next-tier.sh" "$t" prd | tr '\n' ' ')" = "next= on_failure=rollback requires_approval=true " ] || fail "prd"
  if "$A/next-tier.sh" "$t" qa >/dev/null 2>&1; then fail "unknown tier accepted"; fi
}

ok_args() {
  echo "$(yq 'select(.kind=="OCIRepository") | .spec.ref.digest' "$FIX/app/tiers/dev/release.yaml")" \
       "$(jq -r '.client_payload.metadata."release-id"' "$FIX/success.json")"
}

test_verify_ok() {
  d=$(app_checkout)
  # shellcheck disable=SC2046
  [ "$("$A/verify.sh" "$d" dev $(ok_args))" = status=ok ] || fail "current release not ok"
}

test_verify_stale_release() {
  d=$(app_checkout)
  # main moved on: same digest, a shared value changed (and its id updated).
  yq -i '(select(.kind=="HelmRelease") | .spec.values.probe) = "changed"' "$d/tiers/dev/release.yaml"
  "$d/scripts/release-id.sh" --write "$d/tiers/dev/release.yaml"
  # shellcheck disable=SC2046
  [ "$("$A/verify.sh" "$d" dev $(ok_args))" = status=stale ] || fail "old release id accepted"
}

test_verify_stale_digest() {
  d=$(app_checkout)
  # shellcheck disable=SC2046
  set -- $(ok_args)
  [ "$("$A/verify.sh" "$d" dev sha256:1111111111111111111111111111111111111111111111111111111111111111 "$2")" = status=stale ] || fail "wrong digest accepted"
}
