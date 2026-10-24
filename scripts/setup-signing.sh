#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
identity_name='MacRDP Local Code Signing'
certificate="$project_dir/config/MacRDP-Signing.cer"
keychain="$HOME/Library/Keychains/login.keychain-db"
if [[ -f "$certificate" ]]; then
    fingerprint="$(/usr/bin/openssl x509 -inform DER -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
    if ! /usr/bin/security find-identity -p codesigning "$keychain" | /usr/bin/grep -q "$fingerprint"; then
        echo 'The pinned signing certificate exists, but its private key is missing. Restore the original signing identity; do not generate a replacement.' >&2
        exit 1
    fi
    /usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$certificate"
    echo 'Existing MacRDP signing identity is ready.'
    exit 0
fi
if /usr/bin/security find-certificate -c "$identity_name" "$keychain" >/dev/null 2>&1; then
    echo 'An existing MacRDP signing certificate was found. Export its public certificate to config/MacRDP-Signing.cer before continuing.' >&2
    exit 1
fi
umask 077
signing_tmp="$(mktemp -d "${TMPDIR:-/tmp}/macrdp-signing.XXXXXX")"
trap 'rm -rf "$signing_tmp"' EXIT
cat > "$signing_tmp/certificate.conf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = MacRDP Local Code Signing
[signing]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CONFIG
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 7300 \
    -config "$signing_tmp/certificate.conf" -keyout "$signing_tmp/private.key" \
    -out "$signing_tmp/certificate.pem" 2>/dev/null
signing_pass="$(/usr/bin/openssl rand -hex 24)"
/usr/bin/openssl pkcs12 -export -inkey "$signing_tmp/private.key" -in "$signing_tmp/certificate.pem" \
    -name "$identity_name" -out "$signing_tmp/identity.p12" -macalg sha1 \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -passout "pass:$signing_pass"
/usr/bin/security import "$signing_tmp/identity.p12" -f pkcs12 -k "$keychain" -P "$signing_pass" -T /usr/bin/codesign
mkdir -p "$project_dir/config"
/usr/bin/openssl x509 -in "$signing_tmp/certificate.pem" -outform DER -out "$certificate"
chmod 644 "$certificate"
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$certificate"
echo 'Created the reusable signing identity in your login Keychain. Only the public certificate is saved in the project.'
