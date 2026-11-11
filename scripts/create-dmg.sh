#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.."; pwd)"
source "$root/scripts/select-xcode.sh"
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
mkdir "$mount"
if [[ ! -x "$root/.build/dmg-tools/bin/python" ]]; then
    python3 -m venv "$root/.build/dmg-tools"
fi
"$root/.build/dmg-tools/bin/python" -m pip install --require-hashes -r "$root/scripts/dmg-requirements.txt" >/dev/null
xcrun swift "$root/scripts/make-dmg-background.swift" "$stage/background.png"
"$root/.build/dmg-tools/bin/dmgbuild" -s "$root/scripts/dmg-settings.py" \
    -D "app=$app" -D "background=$stage/background.png" NotchCompressor "$output"
hdiutil verify "$output" >/dev/null
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$output" >/dev/null
[[ "$(readlink "$mount/Applications")" == /Applications ]]
[[ -f "$mount/.DS_Store" && -f "$mount/.background.png" ]]
"$root/.build/dmg-tools/bin/python" - "$mount/.DS_Store" <<'PYVERIFY'
import sys
from ds_store import DSStore
with DSStore.open(sys.argv[1], 'r') as store:
    assert store['NotchCompressor.app']['Iloc'] == (180, 190)
    assert store['Applications']['Iloc'] == (480, 190)
    assert store['.']['icvp']['backgroundType'] == 2
PYVERIFY
codesign --verify --deep --strict "$mount/NotchCompressor.app"
hdiutil detach "$mount" >/dev/null
echo "Verified installer: $output"
