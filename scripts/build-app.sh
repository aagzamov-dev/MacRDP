#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_dir/scripts/fetch-sparkle.sh"
"$project_dir/scripts/build-keychain-helper.sh"
configuration="${MACRDP_CONFIGURATION:-Debug}"
identity="$("$project_dir/scripts/signing-identity.sh")"
xcodebuild -project "$project_dir/MacRDP.xcodeproj" -scheme MacRDP \
    -configuration "$configuration" -derivedDataPath "$project_dir/build/app" build "$@" "CODE_SIGN_IDENTITY=$identity"
echo "App: $project_dir/build/app/Build/Products/$configuration/MacRDP.app"
