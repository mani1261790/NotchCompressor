#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Respect an explicit choice. Use a full Xcode for XCTest without changing xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [[ -d "$candidate" ]]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
xcrun swift test "$@"
