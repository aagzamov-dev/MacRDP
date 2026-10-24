#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
helper='Resources/KeychainHelper/MacRDPKeychain'
if [[ -e "$helper" ]]; then
    shasum -a 256 -c Resources/KeychainHelper/SHA256SUMS.txt
    codesign --verify --strict "$helper"
    echo 'Reusing the unchanged credential helper.'
    exit 0
fi
identity="$(./scripts/signing-identity.sh)"
mkdir -p Resources/KeychainHelper build/swift-module-cache
xcrun swiftc -swift-version 6 -O -module-cache-path build/swift-module-cache -target arm64-apple-macos14 \
    Sources/CaptureCore/CredentialMessage.swift Sources/CaptureCore/SecretStore.swift Tools/KeychainHelper/main.swift \
    -o "$helper"
codesign --force --sign "$identity" --timestamp=none --identifier uz.macrdp.keychain "$helper"
codesign --verify --strict "$helper"
shasum -a 256 "$helper" Tools/KeychainHelper/main.swift Sources/CaptureCore/CredentialMessage.swift Sources/CaptureCore/SecretStore.swift > Resources/KeychainHelper/SHA256SUMS.txt
echo 'Created the fixed credential helper. Keep this signed binary unchanged in future releases.'
