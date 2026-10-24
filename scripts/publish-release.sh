#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Usage: scripts/publish-release.sh 0.2.0' >&2; exit 2; fi
if [[ -n "$(git status --porcelain)" ]]; then echo 'Commit and push the reviewed changes before publishing a release.' >&2; exit 1; fi
git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then echo 'Release from the current origin/main commit.' >&2; exit 1; fi
./scripts/test-signing.sh
./scripts/test.sh
./scripts/test-input-queue.sh
./scripts/test-native.sh
./scripts/test-rdp.sh
if [[ ! -f "build/releases/$version/appcast.xml" ]]; then ./scripts/package-release.sh "$version"; fi
commit="$(git rev-parse HEAD)"
if [[ ! -f "build/releases/$version/source-clean" || "$(cat "build/releases/$version/source-commit.txt")" != "$commit" ]]; then
    echo 'The prepared package was not built from this clean commit. Repackage in a fresh release folder.' >&2; exit 1
fi
gh release create "v$version" "build/releases/$version/MacRDP-$version.zip" "build/releases/$version/appcast.xml" "build/releases/$version/MacRDP-$version.dmg" "build/releases/$version/SHA256SUMS.txt" \
    --repo aagzamov-dev/MacRDP --target "$commit" --title "MacRDP $version" --generate-notes --draft
echo "Draft release v$version uploaded. Review it on GitHub, then publish it to make it available to the app’s updater."
