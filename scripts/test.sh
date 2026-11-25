#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
xcrun swift build --product NotchImageWorker
export NOTCH_IMAGE_WORKER="$(xcrun swift build --show-bin-path)/NotchImageWorker"
xcrun swift test "$@"
