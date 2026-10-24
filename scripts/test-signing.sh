#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
identity="$(./scripts/signing-identity.sh)"
./scripts/build-keychain-helper.sh
mkdir -p build/signing-tests build/swift-module-cache
fixture_dir="$(mktemp -d "$project_dir/build/signing-tests/run.XXXXXX")"
account="pc-$(uuidgen)"
cleanup() {
    if [[ -x "$fixture_dir/v1" && -x "$fixture_dir/helper" ]]; then "$fixture_dir/v1" "$fixture_dir/helper" "$account" delete; fi
}
trap cleanup EXIT
xcrun swiftc -swift-version 6 -O -D SIGNING_TEST -module-cache-path build/swift-module-cache \
    Sources/CaptureCore/CredentialMessage.swift Sources/CaptureCore/SecretStore.swift Tools/KeychainHelper/main.swift -o "$fixture_dir/helper"
codesign --force --sign "$identity" --timestamp=none --identifier uz.macrdp.keychain "$fixture_dir/helper"
cp Tests/Signing/host.swift "$fixture_dir/main.swift"
for version in 1 2; do
    flags=(-D BUILD_ONE)
    if [[ "$version" == 2 ]]; then flags=(-D BUILD_TWO); fi
    xcrun swiftc -swift-version 6 -O "${flags[@]}" -module-cache-path build/swift-module-cache \
        Sources/CaptureCore/CredentialMessage.swift "$fixture_dir/main.swift" -o "$fixture_dir/v$version"
    codesign --force --sign "$identity" --timestamp=none --identifier uz.macrdp.app "$fixture_dir/v$version"
    codesign --verify --strict "$fixture_dir/v$version"
    codesign -d -r- "$fixture_dir/v$version" 2>&1 | sed -n 's/^designated => //p' > "$fixture_dir/v$version.requirement"
done
cmp "$fixture_dir/v1.requirement" "$fixture_dir/v2.requirement"
if cmp -s "$fixture_dir/v1" "$fixture_dir/v2"; then echo 'Fixture builds must be different.' >&2; exit 1; fi
"$fixture_dir/v1" "$fixture_dir/helper" "$account" write
"$fixture_dir/v2" "$fixture_dir/helper" "$account" read
cp "$fixture_dir/v2" "$fixture_dir/untrusted"
codesign --force --sign - --identifier uz.macrdp.app "$fixture_dir/untrusted"
"$fixture_dir/untrusted" "$fixture_dir/helper" "$account" denied
"$fixture_dir/v2" "$fixture_dir/helper" "$account" delete
shasum -a 256 -c Resources/KeychainHelper/SHA256SUMS.txt
echo 'PASS: changed app builds access the same synthetic credential without prompts through the unchanged helper; an untrusted caller is rejected. User credentials were not accessed.'
