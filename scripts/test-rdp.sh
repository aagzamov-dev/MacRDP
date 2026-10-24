#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p build/rdp-fixture
openssl req -x509 -newkey rsa:2048 -nodes -keyout build/rdp-fixture/key.pem \
    -out build/rdp-fixture/cert.pem -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 > build/rdp-fixture/certificate-build.txt 2>&1
clang -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    ${MACRDP_TEST_CFLAGS:-} $(pkg-config --cflags freerdp3 freerdp-client3 winpr3) \
    -I Sources/RDPBridge Sources/RDPBridge/RDPBridge.c Tests/RDPBridgeTests/main.c \
    $(pkg-config --libs freerdp3 freerdp-client3 freerdp-server3 winpr3) -framework Security -framework CoreFoundation \
    -o build/macrdp-rdp-tests
./build/macrdp-rdp-tests build/rdp-fixture/cert.pem build/rdp-fixture/key.pem
