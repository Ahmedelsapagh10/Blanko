#!/usr/bin/env bash
set -euo pipefail

sdk=${1:-${ANDROID_HOME:?Android SDK path required}}
tools=${2:-$(find "$sdk/build-tools" -name apksigner -type f | sort -V | tail -1)}
tools=$(dirname "$tools")
platform=$(find "$sdk/platforms" -name android.jar -type f | sort -V | tail -1)
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/blanko-signature-sdk.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
cat > "$fixture_dir/AndroidManifest.xml" <<'MANIFEST'
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.blanko.signaturefixture" android:versionCode="1" android:versionName="1">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />
  <application android:hasCode="false" android:label="Blanko signature fixture" />
</manifest>
MANIFEST
"$tools/aapt" package -f -M "$fixture_dir/AndroidManifest.xml" -I "$platform" -F "$fixture_dir/unsigned.apk"
keytool -genkeypair -keystore "$fixture_dir/fixture.jks" -storetype JKS -storepass fixture-only -keypass fixture-only -alias fixture -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=Blanko Signature Fixture' > /dev/null 2>&1
keytool -exportcert -keystore "$fixture_dir/fixture.jks" -storepass fixture-only -alias fixture 2>/dev/null | openssl dgst -sha256 | awk '{print $NF}' > "$fixture_dir/pin"
"$tools/apksigner" sign --ks "$fixture_dir/fixture.jks" --ks-pass pass:fixture-only --key-pass pass:fixture-only --out "$fixture_dir/signed.apk" "$fixture_dir/unsigned.apk"
echo "Real SDK signer: $tools/apksigner"
"$tools/apksigner" version
"$tools/apksigner" verify --verbose --print-certs "$fixture_dir/signed.apk"
bash tool/verify_android_signature.sh "$tools/apksigner" "$fixture_dir/signed.apk" "$fixture_dir/pin"
