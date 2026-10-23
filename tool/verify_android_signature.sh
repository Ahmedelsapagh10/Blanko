#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo 'Usage: verify_android_signature.sh APKSIGNER APK CERTIFICATE_SHA256_FILE' >&2
  exit 2
fi

expected=$(tr -d '[:space:]' < "$3")
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'Invalid approved Android certificate fingerprint.' >&2
  exit 1
fi

# SDK tools label signers by number, SDK range, or signature scheme.
# Require every reported signing identity to match; exclude source stamps.
actual=$("$1" verify --print-certs "$2" |
  awk -F ': ' '/^(Signer.*|V[0-9]+([.][0-9]+)? Signer.*) certificate SHA-256 digest:/ { print tolower($NF) }' |
  tr -d '\r' | sort -u)
if [[ "$actual" != "$expected" ]]; then
  echo "Android certificate mismatch. Approved: $expected; reported: ${actual:-none}" >&2
  exit 1
fi
echo "Verified Android release certificate: $actual"
