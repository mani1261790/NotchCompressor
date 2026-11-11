#!/bin/bash
set -euo pipefail
app="${1:?app path required}"
output="${2:?new DMG path required}"
[[ -d "$app" && ! -e "$output" ]]
parent="$(cd "$(dirname "$output")"; pwd)"
stage="$(mktemp -d "$parent/.dmg-stage.XXXXXX")"
mount="$stage/mounted"
cleanup() {
    if mount | grep -Fq " on $mount "; then hdiutil detach "$mount" >/dev/null || return; fi
    rm -rf "$stage"
}
trap cleanup EXIT
mkdir "$stage/content" "$mount"
ditto "$app" "$stage/content/NotchCompressor.app"
ln -s /Applications "$stage/content/Applications"
hdiutil create -fs HFS+ -volname NotchCompressor -srcfolder "$stage/content" -format UDZO "$output" >/dev/null
hdiutil verify "$output" >/dev/null
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$output" >/dev/null
[[ "$(readlink "$mount/Applications")" == /Applications ]]
codesign --verify --deep --strict "$mount/NotchCompressor.app"
hdiutil detach "$mount" >/dev/null
echo "Verified installer: $output"
