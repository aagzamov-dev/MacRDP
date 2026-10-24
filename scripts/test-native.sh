#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p build
clang -std=c11 -Wno-deprecated-declarations $(pkg-config --cflags freerdp3 freerdp-client3 winpr3) \
    -c Sources/RDPBridge/RDPBridge.c -o build/bridge.o
native_sources=()
for source in Sources/MacRDP/*.swift; do
    if [[ "$source" != *MacRDPApp.swift ]]; then native_sources+=("$source"); fi
done
xcrun swiftc -swift-version 6 -disable-sandbox -module-cache-path build/swift-module-cache \
    -import-objc-header Sources/RDPBridge/MacRDP-Bridging-Header.h \
    Sources/CaptureCore/*.swift "${native_sources[@]}" build/bridge.o \
    -L/opt/homebrew/lib -lfreerdp-client3 -lfreerdp3 -lwinpr3 -framework Security \
    Tests/NativeSmoke/main.swift -o build/macrdp-native-smoke
./build/macrdp-native-smoke
