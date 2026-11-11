#!/bin/bash
# Release candidate 2. No Apple credentials are needed for a local rehearsal.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
mode="${1:-}"
case "$mode" in check|rehearse|notarize) ;; *) echo "Usage: bash scripts/distribute.sh check|rehearse|notarize" >&2; exit 2;; esac
profile="${NOTCH_NOTARY_PROFILE:-NotchCompressor}"
preflight() {
    local matches count failed=0
    matches="$(security find-identity -v -p codesigning | awk '/"Developer ID Application: / {print $2}')"
    if [[ -n "${NOTCH_SIGNING_SHA1:-}" ]]; then
        matches="$(printf '%s\n' "$matches" | grep -Fxi -- "$NOTCH_SIGNING_SHA1" || true)"
    fi
    count="$(printf '%s\n' "$matches" | awk 'NF {n++} END {print n+0}')"
    if [[ "$count" != 1 ]]; then
        echo "Need one valid Developer ID Application identity with its private key (matched $count). For multiple teams set NOTCH_SIGNING_SHA1." >&2
        failed=1
    else
        identity="$matches"
    fi
    if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null; then
        echo "Configure a working notarytool Keychain profile: $profile" >&2
        failed=1
    fi
    return "$failed"
}
if [[ "$mode" != rehearse ]]; then preflight; fi
if [[ "$mode" == check ]]; then echo "Signing identity and notary profile ready."; exit 0; fi
arch="$(uname -m)"
[[ "$arch" == arm64 ]] || { echo 'This release targets arm64.' >&2; exit 1; }
version=0.1.0-alpha.2
name="NotchCompressor-$version-$arch"
dest="$PWD/dist/$version"
if [[ "$mode" == notarize ]]; then
    [[ ! -e "$dest" && -z "$(git status --porcelain)" ]] || { echo "Use a clean checkout and an unused release directory." >&2; exit 1; }
else
    name="$name-REHEARSAL"
fi

bash scripts/package-release.sh
work="$(mktemp -d "$PWD/dist/.candidate.XXXXXX")"
echo "Private staging and diagnostics: $work"
app="$work/NotchCompressor.app"
ditto dist/NotchCompressor.app "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$app/Contents/Info.plist"
if [[ "$mode" == notarize ]]; then
    bash scripts/sign-app.sh "$app" "$identity"
else
    bash scripts/sign-app.sh "$app"
fi
if [[ "$mode" == notarize ]]; then
    ditto -c -k --keepParent "$app" "$work/submission.zip"
    xcrun notarytool submit "$work/submission.zip" --keychain-profile "$profile" --output-format json > "$work/submission.json"
    submission_id="$(plutil -extract id raw "$work/submission.json")"
    echo "Notary submission: $submission_id"
    if ! xcrun notarytool wait "$submission_id" --keychain-profile "$profile"; then
        xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$work/notary-log.json" || true
        echo "Submission did not finish successfully; inspect $submission_id before resubmitting." >&2
        exit 1
    fi
    xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$work/notary-log.json"
    [[ "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$work/notary-log.json")" == Accepted ]] || { echo "Not accepted; see $work/notary-log.json" >&2; exit 1; }
    xcrun stapler staple "$app"
fi

assets="$work/assets"; mkdir "$assets"
ditto -c -k --sequesterRsrc --keepParent "$app" "$assets/$name.zip"
ditto -x -k "$assets/$name.zip" "$work/extracted"
unpacked="$work/extracted/NotchCompressor.app"
codesign --verify --deep --strict "$unpacked"
"$unpacked/Contents/MacOS/ffmpeg" -version >/dev/null
"$unpacked/Contents/MacOS/ffprobe" -version >/dev/null
if [[ "$mode" == notarize ]]; then
    xcrun stapler validate "$unpacked"
    spctl --assess --type execute --verbose=4 "$unpacked"
fi
bash scripts/create-dmg.sh "$app" "$assets/$name.dmg"
if [[ "$mode" == notarize ]]; then
    codesign --force --timestamp --sign "$identity" "$assets/$name.dmg"
    xcrun notarytool submit "$assets/$name.dmg" --keychain-profile "$profile" --wait --output-format json > "$work/dmg-submission.json"
    dmg_id="$(plutil -extract id raw "$work/dmg-submission.json")"
    xcrun notarytool log "$dmg_id" --keychain-profile "$profile" "$work/dmg-notary-log.json"
    [[ "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$work/dmg-notary-log.json")" == Accepted ]]
    xcrun stapler staple "$assets/$name.dmg"
    xcrun stapler validate "$assets/$name.dmg"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$assets/$name.dmg"
    bash scripts/generate-update-feed.sh "$assets/$name.zip" "$work/feed" "v$version"
    cp "$work/feed/appcast.xml" "$assets/"
fi
cp dist/ffmpeg-9.0.1.tar.xz "$assets/"
ditto dist/build-information "$work/build-information"
git rev-parse HEAD > "$work/build-information/source-commit.txt"
cp scripts/distribute.sh scripts/sign-app.sh scripts/create-dmg.sh scripts/generate-update-feed.sh Package.resolved "$work/build-information/"
ditto -c -k --keepParent "$work/build-information" "$assets/$name-build-information.zip"
(cd "$assets"; shasum -a 256 *.zip *.dmg *.tar.xz > SHA256SUMS.txt
 if [[ -f appcast.xml ]]; then shasum -a 256 appcast.xml >> SHA256SUMS.txt; fi; shasum -a 256 -c SHA256SUMS.txt)
if [[ "$mode" == notarize ]]; then
    mv "$assets" "$dest"; echo "Validated release assets: $dest (not published)"
else
    echo "Local rehearsal only: $assets (not notarized; do not publish)"
fi
