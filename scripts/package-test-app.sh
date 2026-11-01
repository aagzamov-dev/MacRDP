#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
version="${1:-0.3.1}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Use a numeric version, for example 0.3.0.' >&2; exit 2; fi
app_name="MacRDP Test"
bundle_id="uz.macrdp.test"
identity_folder="test-identity"
output="$project_dir/build/macrdp-test-$version"
extra_build_args=()
if [[ "${2:-}" == hardware ]]; then
    app_name="MacRDP Hardware Test"
    bundle_id="uz.macrdp.hardwaretest"
    identity_folder="hardware-test-identity"
    output="$project_dir/build/macrdp-hardware-test-$version"
    prefix="$project_dir/build/hardware-decoding/install"
    [[ -f "$prefix/lib/libfreerdp3.dylib" ]] || { echo 'Build hardware dependencies first'; exit 1; }
    extra_build_args+=("LIBRARY_SEARCH_PATHS=$prefix/lib /opt/homebrew/lib"
        "HEADER_SEARCH_PATHS=$prefix/include/freerdp3 $prefix/include/winpr3 /opt/homebrew/include"
        'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) MACRDP_HARDWARE_TEST=1' 'CURRENT_PROJECT_VERSION=22')
    export MACRDP_BUNDLE_PREFIX="$prefix"
fi
if [[ -e "$output" ]]; then echo "Output already exists: $output" >&2; exit 1; fi
./scripts/fetch-sparkle.sh
./scripts/build-keychain-helper.sh
identity="$(./scripts/signing-identity.sh)"
mkdir -p "build/$identity_folder" build/swift-module-cache
variant_source="$(mktemp -d "$project_dir/build/$identity_folder/source.XXXXXX")"
trap 'rm -rf -- "$variant_source"' EXIT
python3 - "$project_dir" "$variant_source" "$app_name" "$bundle_id" <<'PY'
import pathlib, plistlib, shutil, sys
root, variant = map(pathlib.Path, sys.argv[1:3])
app_name, bundle_id = sys.argv[3:5]
for folder in ('Sources', 'Resources', 'MacRDP.xcodeproj'):
    shutil.copytree(root / folder, variant / folder)
(variant / 'Vendor').symlink_to(root / 'Vendor', target_is_directory=True)
(variant / 'Helper').mkdir()
helper = (root / 'Tools/KeychainHelper/main.swift').read_text()
assert 'uz.macrdp.app' in helper and 'let store = KeychainStore()' in helper
helper = helper.replace('uz.macrdp.app', bundle_id)
helper = helper.replace('let store = KeychainStore()', f'let store = KeychainStore(service: "{bundle_id}.credentials")')
(variant / 'Helper/main.swift').write_text(helper)
store = variant / 'Sources/MacRDP/HelperSecretStore.swift'
source = store.read_text()
assert 'uz.macrdp.keychain' in source
store.write_text(source.replace('uz.macrdp.keychain', bundle_id + '.keychain'))
updater = variant / 'Sources/MacRDP/AppUpdater.swift'
source = updater.read_text()
a = source.index('    func start() {')
b = source.index('    func sessionEnded()', a)
source = source[:a] + '''    func start() {
        automaticChecks = false
        message = "Updates are disabled in MacRDP Test. Install a new test build manually."
    }
    func check() { start() }
''' + source[b:]
updater.write_text(source)
app_delegate = variant / 'Sources/MacRDP/AppDelegate.swift'
app_delegate.write_text(app_delegate.read_text().replace('"MacRDP"', f'"{app_name}"').replace('"Open MacRDP"', f'"Open {app_name}"'))
info_file = variant / 'Resources/Info.plist'
info = plistlib.loads(info_file.read_bytes())
info['CFBundleName'] = app_name
info['CFBundleDisplayName'] = app_name
info['SUEnableAutomaticChecks'] = False
info.pop('SUFeedURL', None)
info_file.write_bytes(plistlib.dumps(info))
PY
helper="$project_dir/build/$identity_folder/MacRDPKeychain"
helper_digest="$(python3 - "$variant_source/Helper/main.swift" Sources/CaptureCore/CredentialMessage.swift Sources/CaptureCore/SecretStore.swift <<'PYHASH'
import hashlib, pathlib, sys
print(hashlib.sha256(b''.join(pathlib.Path(path).read_bytes() for path in sys.argv[1:])).hexdigest())
PYHASH
)"
if [[ ! -f "$helper" || ! -f "$helper.source-sha256" || "$(cat "$helper.source-sha256")" != "$helper_digest" ]]; then
    xcrun swiftc -swift-version 6 -O -module-cache-path build/swift-module-cache -target arm64-apple-macos14 \
        Sources/CaptureCore/CredentialMessage.swift Sources/CaptureCore/SecretStore.swift "$variant_source/Helper/main.swift" -o "$helper"
    codesign --force --sign "$identity" --timestamp=none --identifier "$bundle_id.keychain" "$helper"
    printf '%s\n' "$helper_digest" > "$helper.source-sha256"
fi
codesign --verify --strict "$helper"
cp "$helper" "$variant_source/Resources/KeychainHelper/MacRDPKeychain"
xcodebuild -project "$variant_source/MacRDP.xcodeproj" -scheme MacRDP -configuration Release \
    -derivedDataPath "$variant_source/DerivedData" build \
    "PRODUCT_NAME=$app_name" "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" \
    "MARKETING_VERSION=$version" "CODE_SIGN_IDENTITY=$identity" 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' "${extra_build_args[@]}"
mkdir -p "$output"
ditto "$variant_source/DerivedData/Build/Products/Release/$app_name.app" "$output/$app_name.app"
python3 scripts/bundle-dependencies.py "$output/$app_name.app"
ditto -c -k --sequesterRsrc --keepParent "$output/$app_name.app" "$output/MacRDP-Test-$version.zip"
(cd "$output" && shasum -a 256 "MacRDP-Test-$version.zip") > "$output/SHA256SUMS.txt"
printf 'Separate test app ready: %s\n' "$output/$app_name.app"
