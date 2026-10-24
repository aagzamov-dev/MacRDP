#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
sw_vers
uname -m
xcode-select -p
xcodebuild -version
xcrun swift --version
for tool in brew cmake ninja pkg-config sdl-freerdp; do
    command -v "$tool" || { echo "Missing: $tool" >&2; exit 1; }
done
brew list --versions freerdp sdl3 sdl3_ttf cmake ninja pkgconf
for module in freerdp3 freerdp-client3 winpr3 sdl3; do
    printf '%s: ' "$module"
    pkg-config --modversion "$module"
done
printf 'FreeRDP client version: '
sdl-freerdp /version
echo "Build capabilities are available with: sdl-freerdp /buildconfig"
echo "This command does not connect, inspect credentials, or request input permissions."
