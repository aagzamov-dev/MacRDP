#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD/build/hardware-decoding"
mkdir -p "$root"
archive="$root/freerdp-3.32.2.tar.gz"
if [[ ! -f "$archive" ]]; then
    curl -fL https://github.com/FreeRDP/FreeRDP/archive/refs/tags/3.32.2.tar.gz -o "$archive"
fi
expected=9ccb8357bf0188044a460de775c7ea289ca7d2a2a917eca0f0a7c4dc9c8b08ea
[[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == "$expected" ]]
source_dir="$root/FreeRDP-3.32.2"
if [[ ! -d "$source_dir" ]]; then
    tar -xzf "$archive" -C "$root"
    patch -d "$source_dir" -p1 < patches/freerdp-3.32.2-videotoolbox.patch
else
    patch --dry-run -R -d "$source_dir" -p1 < patches/freerdp-3.32.2-videotoolbox.patch
fi
cmake -S "$source_dir" -B "$root/cmake" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$root/install" -DCMAKE_PREFIX_PATH=/opt/homebrew \
    -DCMAKE_INSTALL_NAME_DIR="$root/install/lib" \
    -DWITH_FFMPEG=ON -DWITH_FFMPEG_HWACCEL=ON -DWITH_GFX_H264=ON \
    -DWITH_CLIENT=OFF -DWITH_CLIENT_COMMON=ON -DWITH_SERVER=OFF -DWITH_SHADOW=OFF \
    -DWITH_SAMPLE=OFF -DWITH_X11=OFF -DWITH_FUSE=OFF -DWITH_CUPS=OFF -DWITH_PCSC=OFF \
    -DWITH_MANPAGES=OFF -DWITH_SWSCALE=ON -DWITH_AAD=OFF -DBUILD_TESTING=OFF
cmake --build "$root/cmake" -j 8
cmake --install "$root/cmake"
