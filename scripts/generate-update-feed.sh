#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config/release.env
archive="${1:?signed notarized ZIP path required}"
dest="${2:?new feed staging directory required}"
tag="${3:?GitHub release tag required}"
[[ "$tag" == "v$NOTCH_RELEASE_VERSION" && ! -e "$dest" ]] || { echo "Use the configured release tag and a new feed directory." >&2; exit 1; }
[[ "$archive" != *REHEARSAL* ]] || { echo 'Never publish a rehearsal.' >&2; exit 1; }
verification="$(mktemp -d "$PWD/.build/feed-verification.XXXXXX")"
trap 'rm -rf "$verification"' EXIT
ditto -x -k "$archive" "$verification"
app="$verification/NotchCompressor.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$NOTCH_BUILD_NUMBER" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$NOTCH_MARKETING_VERSION" ]] || { echo 'Archive version does not match config/release.env.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
tools="$(bash scripts/sparkle-tools.sh)"
account=com.mani.NotchCompressor
[[ "$("$tools/generate_keys" --account "$account" -p)" == "$(cat config/sparkle-public-key.txt)" ]] || { echo 'Sparkle public key mismatch.' >&2; exit 1; }
mkdir -p "$dest"
# Only update archives go here; never license/build-info ZIPs.
cp "$archive" "$dest/"
"$tools/generate_appcast" --account "$account" --download-url-prefix "https://github.com/mani1261790/NotchCompressor/releases/download/$tag/" "$dest"
"$tools/sign_update" --account "$account" --verify "$dest/appcast.xml"
echo "Staged feed only: $dest/appcast.xml. Publish the archive before promoting this feed."
