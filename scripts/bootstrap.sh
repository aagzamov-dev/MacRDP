#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
xcrun --find clang >/dev/null
xcodebuild -version
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew bundle install --file="$project_dir/Brewfile" --no-upgrade
"$project_dir/scripts/doctor.sh"
"$project_dir/scripts/build-probe.sh"
