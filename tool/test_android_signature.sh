#!/usr/bin/env bash
set -euo pipefail

fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/blanko-signature-test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
expected=$(printf 'a%.0s' {1..64})
other=$(printf 'b%.0s' {1..64})
printf '%s\n' "$expected" > "$fixture_dir/pin"
cat > "$fixture_dir/apksigner" <<'FAKE'
#!/usr/bin/env bash
cat "$SIGNATURE_FIXTURE"
exit "${SIGNATURE_STATUS:-0}"
FAKE
chmod +x "$fixture_dir/apksigner"
export SIGNATURE_FIXTURE="$fixture_dir/output"
export SIGNATURE_STATUS=0
checks=0
check() {
  printf '%s\n' "$2" > "$SIGNATURE_FIXTURE"
  result=0
  bash tool/verify_android_signature.sh "$fixture_dir/apksigner" unused.apk "$fixture_dir/pin" > "$fixture_dir/result" 2>&1 || result=$?
  if [[ "$1" == pass && "$result" != 0 ]] || [[ "$1" == fail && "$result" == 0 ]]; then
    cat "$fixture_dir/result" >&2
    echo "Signature check $((checks + 1)) failed." >&2
    exit 1
  fi
  checks=$((checks + 1))
}

check pass "Signer #1 certificate SHA-256 digest: $expected"
check pass "Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate SHA-256 digest: $expected"
check pass "$(printf 'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: %s\nSigner (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: %s' "$expected" "$expected")"
check fail "Signer #1 certificate SHA-256 digest: $other"
check fail "$(printf 'Signer #1 certificate SHA-256 digest: %s\nSigner #2 certificate SHA-256 digest: %s' "$expected" "$other")"
check fail "Source Stamp Signer certificate SHA-256 digest: $expected"
check fail "$(printf 'Signer #1 certificate SHA-256 digest: %s\nSource Stamp Signer certificate SHA-256 digest: %s' "$other" "$expected")"
check fail ''
SIGNATURE_STATUS=1
check fail "Signer #1 certificate SHA-256 digest: $expected"
echo "$checks Android signature guard cases passed."
