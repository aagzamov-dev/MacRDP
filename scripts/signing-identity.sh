#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
certificate="$project_dir/config/MacRDP-Signing.cer"
if [[ ! -f "$certificate" ]]; then echo 'Run scripts/setup-signing.sh once before building.' >&2; exit 1; fi
fingerprint="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
if ! /usr/bin/security find-identity -p codesigning | /usr/bin/grep -q "$fingerprint"; then
    echo 'The original MacRDP signing private key is unavailable. Restore it to Keychain; ad-hoc fallback is disabled.' >&2
    exit 1
fi
printf '%s\n' "$fingerprint"
