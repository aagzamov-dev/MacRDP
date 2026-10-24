#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${MACRDP_CONFIGURATION:-Debug}"
xcodebuild -project "$project_dir/MacRDP.xcodeproj" -scheme MacRDP \
    -configuration "$configuration" -derivedDataPath "$project_dir/build/app" build "$@"
echo "App: $project_dir/build/app/Build/Products/$configuration/MacRDP.app"
