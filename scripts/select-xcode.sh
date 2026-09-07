#!/bin/bash
# Sourced by build/test scripts; never changes the system xcode-select setting.
notch_sdk_is_supported() {
    local notch_sdk_version
    notch_sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" || return 1
    [[ "${notch_sdk_version%%.*}" -ge 26 ]] && xcrun xcodebuild -version >/dev/null 2>&1
}
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    if ! notch_sdk_is_supported; then
        for notch_xcode in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode_*.app/Contents/Developer; do
            [[ -d "$notch_xcode" ]] || continue
            if (export DEVELOPER_DIR="$notch_xcode"; notch_sdk_is_supported); then
                export DEVELOPER_DIR="$notch_xcode"
                break
            fi
        done
    fi
fi
if ! notch_sdk_is_supported; then
    echo 'NotchCompressor requires Xcode 26 or newer (macOS SDK 26+). Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
    exit 1
fi
unset -f notch_sdk_is_supported
unset notch_xcode
