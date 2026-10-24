#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/build/swift-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/build/swift-module-cache"
swift test --disable-sandbox --cache-path "$project_dir/build/package-cache" \
    -Xswiftc -module-cache-path -Xswiftc "$project_dir/build/swift-module-cache"
