#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Usage: scripts/package-release.sh 0.2.0 [build-number]' >&2; exit 2; fi
build_number="${2:-$(date -u +%Y%m%d%H%M%S)}"
if [[ ! "$build_number" =~ ^[0-9]+$ ]]; then echo 'Build number must be numeric.' >&2; exit 2; fi
./scripts/fetch-sparkle.sh
public_key="$(Vendor/Sparkle/bin/generate_keys --account uz.macrdp.updates -p)"
expected_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
if [[ "$public_key" != "$expected_key" ]]; then echo 'The update signing key does not match this app. Restore the original key before publishing.' >&2; exit 1; fi
MACRDP_CONFIGURATION=Release ./scripts/build-app.sh "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build_number" 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'
staging="${MACRDP_RELEASE_DIR:-$project_dir/build/releases/$version}"
if [[ -e "$staging" ]]; then echo "Release folder already exists: $staging. Use a new version or inspect the existing package." >&2; exit 1; fi
mkdir -p "$staging"
git rev-parse HEAD > "$staging/source-commit.txt"
if [[ -z "$(git status --porcelain)" ]]; then touch "$staging/source-clean"; fi
ditto build/app/Build/Products/Release/MacRDP.app "$staging/MacRDP.app"
python3 scripts/bundle-dependencies.py "$staging/MacRDP.app"
ditto -c -k --sequesterRsrc --keepParent "$staging/MacRDP.app" "$staging/MacRDP-$version.zip"
Vendor/Sparkle/bin/generate_appcast --account uz.macrdp.updates --maximum-deltas 0 \
    --download-url-prefix "https://github.com/aagzamov-dev/MacRDP/releases/download/v$version/" \
    -o "$staging/appcast.xml" "$staging"
./scripts/create-installer.sh "$version" "$staging"
(cd "$staging" && shasum -a 256 "MacRDP-$version.zip" "MacRDP-$version.dmg") > "$staging/SHA256SUMS.txt"
echo "Signed release ready: $staging"
