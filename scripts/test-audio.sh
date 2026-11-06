#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
prefix="$PWD/build/hardware-decoding/install"
[[ -f "$prefix/lib/libfreerdp-client3.dylib" ]] || { echo 'Build hardware dependencies first'; exit 1; }
clang -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -I"$prefix/include/freerdp3" -I"$prefix/include/winpr3" \
    Tests/RDPBridgeTests/audio.c -L"$prefix/lib" -lfreerdp-client3 -lfreerdp3 -lwinpr3 \
    -framework Security -framework CoreFoundation -Wl,-headerpad_max_install_names -o build/macrdp-audio-tests
./build/macrdp-audio-tests
clang -std=c11 -Wno-deprecated-declarations \
    -I"$prefix/include/freerdp3" -I"$prefix/include/winpr3" \
    -Ibuild/hardware-decoding/FreeRDP-3.32.2/channels/audin/client \
    Tests/RDPBridgeTests/audio-formats.m -L"$prefix/lib" -lfreerdp-client3 -lfreerdp3 -lwinpr3 \
    -framework AVFoundation -framework CoreAudio -framework AudioToolbox \
    -framework ApplicationServices -o build/macrdp-audio-format-tests
./build/macrdp-audio-format-tests
