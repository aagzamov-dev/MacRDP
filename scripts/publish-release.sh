#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
version="${1:-}"
mode="${2:---draft}"
if [[ "$mode" != --draft && "$mode" != --publish ]]; then echo 'Use --draft or --publish.' >&2; exit 2; fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Usage: scripts/publish-release.sh 0.2.0' >&2; exit 2; fi
if [[ -n "$(git status --porcelain)" ]]; then echo 'Commit and push the reviewed changes before publishing a release.' >&2; exit 1; fi
git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then echo 'Release from the current origin/main commit.' >&2; exit 1; fi
./scripts/test-signing.sh
./scripts/test.sh
./scripts/test-input-queue.sh
./scripts/test-native.sh
./scripts/test-rdp.sh
bash scripts/test-clipboard.sh
bash scripts/test-clipboard-settings.sh
bash scripts/test-display-updates.sh
bash scripts/build-hardware-dependencies.sh
bash scripts/test-audio.sh
bash scripts/test-hardware-decoding.sh
if [[ ! -f "build/releases/$version/appcast.xml" ]]; then ./scripts/package-release.sh "$version"; fi
commit="$(git rev-parse HEAD)"
if [[ ! -f "build/releases/$version/source-clean" || "$(cat "build/releases/$version/source-commit.txt")" != "$commit" ]]; then
    echo 'The prepared package was not built from this clean commit. Repackage in a fresh release folder.' >&2; exit 1
fi
release_args=(--draft)
if [[ "$mode" == --publish ]]; then release_args=(--latest); fi
gh release create "v$version" "build/releases/$version/MacRDP-$version.zip" "build/releases/$version/appcast.xml" "build/releases/$version/MacRDP-$version.dmg" "build/releases/$version/SHA256SUMS.txt" \
    --repo aagzamov-dev/MacRDP --target "$commit" --title "MacRDP $version" --notes-file docs/RELEASE-NOTES.md "${release_args[@]}"
echo "Release v$version uploaded ($mode): https://github.com/aagzamov-dev/MacRDP/releases/tag/v$version"
