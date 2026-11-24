# NotchCompressor

[日本語](README.md)

A macOS app built with SwiftUI that compresses screen recordings dropped near the notch at the top of your screen.

| Left | Center | Right |
| --- | --- | --- |
| Video only | Video and audio | Audio only |
| Keep audio | Re-encode both tracks | Keep video |

The drop panel expands only while you drag files toward it. Drop multiple videos together, or add more while compression is running. Open the queue from the menu bar to check progress, or use its **+** button to add videos and choose a mode.

**Successful compression replaces the original file.** The app writes temporary output and validates it by decoding the entire result before replacing the original at the same location. It preserves the MOV/MP4/M4V container extension. Failed or cancelled tasks, and tasks whose original file changed during processing, do not replace the original. After replacement, the uncompressed original is no longer available. In the currently published alpha.2, output can be larger than the original.

## Install the Apple Silicon preview

Requires macOS 14 or later and Apple Silicon.

1. Download `NotchCompressor-0.1.0-alpha.2-arm64.dmg` from the [alpha.2 release](https://github.com/mani1261790/NotchCompressor/releases/tag/v0.1.0-alpha.2).
2. Open the DMG and drag `NotchCompressor.app` to Applications.
3. Open the app from Applications. It runs in the menu bar and near the notch.

The published app and DMG are Developer ID signed and notarized by Apple. No quarantine-removal command is needed. Release assets include `SHA256SUMS.txt` for checksum verification.

**Alpha.2 has a Japanese interface and installer.** The English interface described below is under development and has not been released yet.

Alpha.1 does not support automatic updates: install alpha.2 manually using the DMG. Alpha.2 can check for updates from Settings or the menu bar. Automatic checks are off by default.

### Preview limitations

Some interactions still need real-device verification, including Finder drops after the Mission Control fix, additional displays, full-screen apps, login launch, and first launch after download. Representative screen recordings still need quality review. See the [validation record (Japanese)](docs/VALIDATION.md).

## Next version — not yet released

Development builds include these changes; the published alpha.2 does not:

- Keep the original when compressed output is the same size or larger. Discard temporary output and report completion without size reduction.
- Pause active processing for system sleep, then remove only the sleep pause on wake. Tasks paused manually stay paused. If the destination is inaccessible, show recovery advice. Display sleep alone does not pause processing. Actual system sleep/wake testing remains outstanding.
- Preserve the original frame timing by default for new settings, including variable frame rates. An explicit **Up to 30 fps** option uses evenly spaced frames. Existing settings and queued tasks retain their previous frame rate behavior. Audio-only compression continues to copy video unchanged.
- Provide Japanese and English interfaces, selected using the macOS per-app language preference, with English as the fallback. Separate installer languages are being prepared. Real-device layout and dependency-dialog checks remain outstanding.

The sections below describe the published alpha.2.

## Configure compression

Settings offers three presets and Custom. Custom sets video bitrate to 10–100% of the original in 1% steps, and audio bitrate to 32–256 kbps in 8 kbps steps. For example, 50% video bitrate and 80 kbps audio.

Changes are saved automatically and apply to newly added videos. Queued videos retain their settings; retrying uses the current settings. Video-only mode keeps audio unchanged, and audio-only mode keeps video unchanged.

A 50% video bitrate does not guarantee half the file size. If the original video bitrate is unknown, it is estimated from file size and duration. Custom video targets are bounded to 32 kbps–100 Mbps. Audio targets are capped at the original bitrate, with a minimum of 32 kbps.

| Preset | Ceiling used for automatic video bitrate | Audio target |
| --- | --- | --- |
| Higher quality | About 85% of original bitrate | AAC 128 kbps |
| Balanced | About 65% of original bitrate | AAC 96 kbps |
| Smaller files | About 45% of original bitrate | AAC 64 kbps |

The presets compare resolution × fps (up to 30) × a coefficient (0.09, 0.06, or 0.035) with the original-bitrate ceiling, use the lower value, and bound it to 150 kbps–12 Mbps. These percentages are not file-size reduction targets.

All presets use the same codecs: hardware HEVC (H.265) for video and AAC for audio. Video resolution is preserved. In alpha.2, video above 30 fps is generally reduced to 30 fps when re-encoded. Unchanged tracks are copied without re-encoding. Custom replaces the automatic video calculation with the chosen percentage. Re-encoding is lossy; lost quality cannot be recovered.

### Hardware encoding and speed

Both Standard and Faster encoding use the Mac's hardware HEVC encoder. Standard is the default. Faster encoding requests a preference for speed, which may change quality and compression efficiency at the same target bitrate. It has no effect on unsupported hardware. It applies to newly added videos in Video only or Video and audio mode, not Audio only or output validation.

A synthetic-video test on an M2 reduced encoding time by about 36%. This is not a prediction for real screen recordings or other Macs. See [measurement conditions (Japanese)](docs/PERFORMANCE.md).

## Queue controls

- **Automatic (default):** up to two tasks, with at most one video encode and an audio-only task in a spare slot. Low Power Mode, elevated thermal state, less than 8 GB of memory, or fewer than four logical CPUs limits newly started tasks to one.
- **One at a time / Up to two at a time:** choose from the queue. Changing the setting does not terminate running tasks.
- **Reorder:** drag a task that is not running onto another eligible task. The insertion line shows its new position. Running and stopping tasks stay at the top. There is no separate priority setting.
- **Pause / Resume:** each task keeps its unfinished output and process so it can continue from the same point while the app remains open.
- **Remove:** remove waiting, paused, or finished tasks individually. Removing a paused task ends its process and discards unfinished output. Original videos are kept.

There is no global pause button. Added videos start when resources are available. Paused tasks retain their execution slot and exclusive access to their original file; resume or remove them to free that slot. Scheduling may start a compatible audio-only task ahead of a waiting video task when that is the available resource.

Completed tasks leave the visible queue. The menu bar shows active, paused, or attention-needed counts. A completion summary shows before/after sizes and the difference for eight seconds, grouping consecutive completions. Alpha.2 reports increases when output grows.

## Login, notifications, and background processing

Enable Launch at login in Settings to run the app after your next login. If macOS approval is needed, use Review Login Items. The queue window does not open automatically at login.

Notifications are off by default. Enable completion/failure notifications and grant permission in macOS. Completion notifications show measured before/after sizes; failures show recovery advice. Clicking a notification opens the queue. Video names and paths are excluded. Cancellation and restored history do not trigger notifications. Focus settings may hide banners; results remain available in the queue.

Low-space errors show available space, estimated required space, and the shortfall when known. Compression needs room for temporary output alongside the original. Free space on the same disk, or move the original video to a disk with enough space and add it again. Moving between folders on the same disk does not free space. The app does not delete unrelated files.

Switching apps, closing the queue window, locking the screen, or turning off the display does not cancel compression. Active processing suppresses App Nap and idle sleep without preventing display sleep. The assertion is released when every task is paused or work finishes. In alpha.2, continuation after closing the lid, manual sleep, logout, restart, or quitting is not guaranteed. Keep the Mac awake with its lid open for long jobs. Quitting with unfinished work asks for confirmation and waits for cancellation.

## Supported files and recovery

- Local MOV, MP4, and M4V files with one supported video track and at most one audio track.
- Video compression supports opaque, 8-bit SDR video. Audio compression supports mono or stereo audio.
- Audio-only mode rejects videos without audio. Video and audio mode compresses only video if no audio exists.
- Unsupported colors, bit depths, transparency, or container/track combinations may be rejected. Download cloud-only videos in Finder before adding them.
- Quality defaults are provisional; readability and audio quality on representative recordings still need evaluation.

Settings and history are stored in `~/Library/Application Support/com.mani.NotchCompressor/queue.json`. Up to 100 recent successful results are retained internally, but hidden from the queue. Clearing history does not delete videos. Corrupted history is not overwritten; the app shows a storage error.

After restarting, unfinished tasks are marked interrupted and are not automatically re-encoded. Retrying starts from the beginning. A crash or force quit may leave a `.notchcompressor-UUID` temporary directory beside the original; this is not completed output. Normal cancellation and quitting clean up the task's temporary output.

The compact black notch area stays visible while idle. On displays without a notch, it uses a small 180 × 28 pt area.

## Shortcuts and diagnostics

Set a global shortcut to open the queue in Settings. None is assigned by default. The × button clears it. The shortcut opens the queue without adding videos or starting compression.

View and copy diagnostics from Settings → Support. The report excludes video names, paths, content, and raw logs, and is not sent automatically. Review it before including it in a bug report.

## Build and test

Requires Xcode 26 or later with a macOS 26 or later SDK. Open `Package.swift` in Xcode, or run:

```sh
bash scripts/build-app.sh
open dist/NotchCompressor.app
```

The app targets the build Mac's architecture and uses an ad-hoc signature for local execution. It bundles FFmpeg 9.0.1 built from pinned sources. The first build downloads and compiles dependencies. The minimum runtime remains macOS 14; older macOS versions use fallback controls instead of Liquid Glass.

```sh
bash scripts/format.sh check
python3 scripts/check-localization.py
bash scripts/test.sh
# Include real FFmpeg / VideoToolbox integration tests:
NOTCH_FFMPEG_DIR="$PWD/.build/vendor/install-$(uname -m)/bin" NOTCH_MEDIA_TESTS=1 bash scripts/test.sh
```

Use `bash scripts/format.sh write` to format Swift. Build/test scripts select a suitable installed Xcode for the command without changing system `xcode-select`; an explicit `DEVELOPER_DIR` takes precedence. Integration tests create synthetic videos in temporary folders and do not use your existing videos.

See the [release guide (Japanese)](docs/DEVELOPER_ID_RELEASE.md), [validation record (Japanese)](docs/VALIDATION.md), [plan (Japanese)](PLAN.md), and [GitHub Issues](https://github.com/mani1261790/NotchCompressor/issues).

## License

The app is licensed under [Apache License 2.0](LICENSE). Bundled FFmpeg uses LGPL 2.1 or later; see [third-party notices](THIRD_PARTY_NOTICES.md). Open licenses from Settings. Distributions must include the matching FFmpeg source and build information alongside the app and checksums; `scripts/package-release.sh` prepares these artifacts.
