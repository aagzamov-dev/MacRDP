#!/bin/bash
set -euo pipefail
if [[ $# -eq 1 && "$1" == "--help" ]]; then
    echo "Usage: $0 HOST WINDOWS_USERNAME"
    echo "Starts the upstream SDL client windowed, without exclusive keyboard grab."
    echo "Enter your password only in the client's prompt. Certificate checks remain enabled."
    echo "This may reconnect the Windows session currently used by Windows App."
    exit 0
fi
if [[ $# -ne 2 || -z "$1" || -z "$2" || "$1" == -* || "$2" == -* ]]; then
    echo "Usage: $0 HOST WINDOWS_USERNAME (never supply a password)" >&2
    exit 2
fi
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v sdl-freerdp >/dev/null
umask 077
export XDG_CONFIG_HOME="$project_dir/build/baseline-config"
mkdir -p "$XDG_CONFIG_HOME"
exec sdl-freerdp "/v:$1" "/u:$2" /sec:nla /size:1280x800 \
    +dynamic-resolution -grab-keyboard -clipboard /log-level:WARN
