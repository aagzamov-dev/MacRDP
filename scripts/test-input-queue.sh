#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p build
clang -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    ${MACRDP_TEST_CFLAGS:-} $(pkg-config --cflags freerdp3 freerdp-client3 winpr3) \
    Tests/RDPBridgeTests/queue.c $(pkg-config --libs freerdp3 freerdp-client3 winpr3) \
    -framework Security -framework CoreFoundation -o build/macrdp-input-queue-tests
./build/macrdp-input-queue-tests
