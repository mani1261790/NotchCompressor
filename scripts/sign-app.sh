#!/bin/bash
set -euo pipefail
app="${1:?app path required}"
identity="${2:--}"
sign=(--force --options runtime --sign "$identity")
if [[ "$identity" != - ]]; then sign+=(--timestamp); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
for item in "$framework/Versions/B/XPCServices/Installer.xpc" \
            "$framework/Versions/B/XPCServices/Downloader.xpc" \
            "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" \
            "$framework" "$app/Contents/MacOS/ffmpeg" "$app/Contents/MacOS/ffprobe" "$app"; do
    if [[ "$item" == */Downloader.xpc ]]; then
        codesign "${sign[@]}" --preserve-metadata=entitlements "$item"
    else
        codesign "${sign[@]}" "$item"
    fi
    codesign --verify --strict "$item"
    details="$(codesign --display --verbose=4 "$item" 2>&1)"
    grep -Eq 'flags=.*runtime' <<< "$details"
    if [[ "$identity" != - ]]; then
        grep -q '^Authority=Developer ID Application:' <<< "$details"
        grep -q '^Timestamp=' <<< "$details"
    fi
done
codesign --verify --deep --strict "$app"
