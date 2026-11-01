#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD/build/hardware-decoding"
prefix="$root/install"
ffmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x64:rate=1' \
    -frames:v 1 -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
    -f h264 -y "$root/synthetic.h264"
clang -std=c11 -Wno-deprecated-declarations -I"$prefix/include/freerdp3" -I"$prefix/include/winpr3" \
    Tests/RDPBridgeTests/decoder.c -L"$prefix/lib" -lfreerdp3 -lwinpr3 -o "$root/decoder-test"
FREERDP_HWCTX_TYPE=videotoolbox "$root/decoder-test" "$root/synthetic.h264" "$root/hardware.bgra" 2
FREERDP_HWCTX_TYPE=vaapi "$root/decoder-test" "$root/synthetic.h264" "$root/fallback.bgra" 1
python3 - "$root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
a = (root / 'hardware.bgra').read_bytes()
b = (root / 'fallback.bgra').read_bytes()
assert len(a) == len(b) == 64 * 64 * 4
differences = [abs(x-y) for i, (x,y) in enumerate(zip(a,b)) if i % 4 != 3]
assert max(differences) <= 4
print('PASS synthetic hardware/software output comparison; max channel difference:', max(differences))
PY
