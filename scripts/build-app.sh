#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/select-xcode.sh
bash scripts/build-ffmpeg.sh
xcrun swift build -c release
bin_dir="$(xcrun swift build -c release --show-bin-path)"
app_dir="$PWD/dist/NotchCompressor.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/Licenses"
cp ".build/vendor/install-$(uname -m)/bin/ffmpeg" ".build/vendor/install-$(uname -m)/bin/ffprobe" "$app_dir/Contents/MacOS/"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/Licenses/"
cp .build/vendor/ffmpeg-9.0.1/COPYING.LGPLv2.1 "$app_dir/Contents/Resources/Licenses/FFmpeg-LGPL-2.1.txt"
cp .build/vendor/ffmpeg-9.0.1/LICENSE.md "$app_dir/Contents/Resources/Licenses/FFmpeg-LICENSE.md"
xcrun swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
cp "$bin_dir/NotchCompressor" "$app_dir/Contents/MacOS/NotchCompressor"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NotchCompressor</string>
<key>CFBundleIdentifier</key><string>com.mani.NotchCompressor</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.mani.NotchCompressor.queue-job</string>
<key>UTTypeDescription</key><string>NotchCompressor queue item</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>NotchCompressor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir/Contents/MacOS/ffmpeg"
codesign --force --sign - "$app_dir/Contents/MacOS/ffprobe"
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
