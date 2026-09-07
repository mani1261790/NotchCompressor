#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
bash scripts/build-app.sh
app="$PWD/dist/NotchCompressor.app"
arch="$(uname -m)"
name="NotchCompressor-0.1.0-alpha.1-$arch"
codesign --verify --deep --strict "$app"
for tool in ffmpeg ffprobe; do
  dependencies="$(otool -L "$app/Contents/MacOS/$tool" | tail -n +2)"
  if printf '%s\n' "$dependencies" | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' ; then
    echo "Non-system dependency detected" >&2; exit 1
  fi
done
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$name.zip"
cp .build/vendor/ffmpeg-9.0.1.tar.xz dist/
info="dist/build-information"
mkdir -p "$info"
cp scripts/build-ffmpeg.sh "$info/"
cp ".build/vendor/install-$arch/config.h" "$info/"
"$app/Contents/MacOS/ffmpeg" -buildconf > "$info/ffmpeg-buildconf.txt" 2>&1
xcrun clang --version > "$info/compiler.txt"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$info/"
ditto -c -k --keepParent "$info" "dist/$name-build-information.zip"
(cd dist && shasum -a 256 "$name.zip" "$name-build-information.zip" ffmpeg-9.0.1.tar.xz > SHA256SUMS.txt)
