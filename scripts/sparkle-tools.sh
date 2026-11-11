#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$PWD/.build/sparkle-tools/2.10.1"
mkdir -p "$dir"
archive="$dir/Sparkle.tar.xz"
if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$archive"
fi
echo "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  $archive" | shasum -a 256 --check >/dev/null
# Always extract the verified archive rather than trusting a cached executable.
tar -xf "$archive" -C "$dir"
printf '%s\n' "$dir/bin"
