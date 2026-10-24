#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
staging="${2:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! -d "$staging/MacRDP.app" ]]; then
    echo 'Usage: scripts/create-installer.sh version release-folder' >&2; exit 2
fi
installer="$staging/MacRDP-$version.dmg"
if [[ -e "$installer" ]]; then echo 'Installer already exists; use a new release folder.' >&2; exit 1; fi
installer_tmp="$(mktemp -d "${TMPDIR:-/tmp}/macrdp-installer.XXXXXX")"
trap 'rm -rf "$installer_tmp"' EXIT
ditto "$staging/MacRDP.app" "$installer_tmp/MacRDP.app"
ln -s /Applications "$installer_tmp/Applications"
cat > "$installer_tmp/Install MacRDP.txt" <<'TEXT'
MacRDP — installation

1. Quit the running MacRDP app before replacing it.
2. Drag MacRDP into Applications. Choose Replace if an older copy is installed.
3. Open MacRDP from Applications and keep using that copy.
4. If macOS blocks first launch, use System Settings > Privacy & Security > Open Anyway.
5. Unlock with your existing MacRDP PIN. Saved PCs and Keychain passwords are preserved.

This build uses a persistent local signing certificate, without Apple Developer ID or notarization.
When upgrading the old app, macOS may ask once per saved item for MacRDPKeychain access.
Choose Always Allow for this bundled credential helper. The helper stays unchanged in future app updates.
Keyboard Accessibility permission is separate: use Keyboard setup & permissions in the app.

For future updates, use Updates in MacRDP once a newer GitHub release is published.
TEXT
hdiutil create -volname "MacRDP $version" -srcfolder "$installer_tmp" -format UDZO "$installer"
hdiutil verify "$installer"
echo "Drag-to-Applications installer: $installer"
