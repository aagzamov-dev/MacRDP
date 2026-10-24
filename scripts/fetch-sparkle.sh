#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
folder="$project_dir/Vendor/Sparkle"
if [[ -f "$folder/.version" && "$(cat "$folder/.version")" == "$version" && -x "$folder/bin/generate_appcast" && -d "$folder/Sparkle.framework" ]]; then exit 0; fi
archive="$(mktemp -t macrdp-sparkle)"
trap 'rm -f "$archive"' EXIT
curl --fail --location --silent --show-error "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
mkdir -p "$folder"
tar -xf "$archive" -C "$folder" ./Sparkle.framework ./bin ./LICENSE
printf '%s\n' "$version" > "$folder/.version"
