#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
version=9.0.1
sha=cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
vendor="$PWD/.build/vendor"
archive="$vendor/ffmpeg-$version.tar.xz"
prefix="$vendor/install-$(uname -m)"
mkdir -p "$vendor"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$archive"
fi
printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 --check
stamp="$(shasum -a 256 "$0" | cut -d ' ' -f 1)"
if [[ -x "$prefix/bin/ffmpeg" && -f "$prefix/build-stamp" && "$(cat "$prefix/build-stamp")" == "$stamp" ]]; then exit 0; fi
source_dir="$vendor/ffmpeg-$version"
[[ -d "$source_dir" ]] || tar -xf "$archive" -C "$vendor"
build_dir="$vendor/build-$(uname -m)"
mkdir -p "$build_dir"
cd "$build_dir"
export MACOSX_DEPLOYMENT_TARGET=14.0
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
"$source_dir/configure" --prefix="$prefix" --cc="$(xcrun -f clang)" \
  --disable-autodetect --disable-network --disable-doc --disable-debug \
  --disable-ffplay --disable-shared --enable-static --disable-gpl --disable-nonfree \
  --disable-x86asm --enable-videotoolbox --enable-audiotoolbox \
  --extra-cflags=-mmacosx-version-min=14.0 --extra-ldflags=-mmacosx-version-min=14.0
make -j "$(sysctl -n hw.activecpu)"
make install
cp config.h "$prefix/config.h"
printf '%s\n' "$stamp" > "$prefix/build-stamp"
