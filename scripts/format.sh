#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
case "${1:-check}" in
    check) mode=(lint --strict) ;;
    write) mode=(format --in-place) ;;
    *) echo 'Usage: bash scripts/format.sh check|write' >&2; exit 2 ;;
esac
xcrun swift-format --version
xcrun swift-format "${mode[@]}" --configuration .swift-format --recursive Package.swift Sources Tests scripts
