#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cmake -S "$project_dir" -B "$project_dir/build/dependency-probe" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "$project_dir/build/dependency-probe"
"$project_dir/build/dependency-probe/macrdp-dependency-probe"
