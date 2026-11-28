# NotchCompressor

[Product page](https://mani1261790.github.io/NotchCompressor/?lang=en)

[日本語](README.md)

A macOS app built with SwiftUI that compresses screen recordings dropped near the notch at the top of your screen.

| Left | Center | Right |
| --- | --- | --- |
| Video only | Video and audio | Audio only |
| Keep audio | Re-encode both tracks | Keep video |

The drop panel expands when you drag files toward it. Drop multiple videos together, or add more while compression is running. Open the queue from the menu bar to check progress, or use its **+** button to add videos and choose a mode.

**Only smaller output that passes validation replaces the original.** The app writes temporary output and decodes the entire result before replacing the original at the same location, preserving the MOV/MP4/M4V container. Failure, cancellation, no size reduction, or a changed original keeps the original. After replacement, the uncompressed original is no longer available; keep a separate copy if needed.

## Install on Apple Silicon

Requires macOS 14 or later and Apple Silicon.

1. Download `NotchCompressor-0.2.1-arm64-en.dmg` from the [0.2.1 release](https://github.com/mani1261790/NotchCompressor/releases/tag/v0.2.1).
2. Open the DMG and drag `NotchCompressor.app` to Applications.
3. Open the app from Applications. It runs in the menu bar and near the notch.

The published app and DMG are Developer ID signed and notarized by Apple. No quarantine-removal command is needed. Release assets include `SHA256SUMS.txt` for checksum verification.

The app supports Japanese and English. The two DMGs have different installer instructions but contain the same app. The interface follows the macOS per-app language preference; restart the app after changing it.

Alpha.1 does not support automatic updates: install the latest version manually using the DMG. Alpha.2 can check for updates from Settings or the menu bar. Automatic checks are on for new installations. Existing preferences are preserved.

If alpha.2 stays open after you choose Install and Relaunch, close Settings and choose Quit NotchCompressor from the app menu. The update will finish and relaunch the app. This issue is fixed in 0.1.0.

## Images, audio, and notch widgets

Add JPEG, PNG, and AAC M4A files alongside videos. Configure JPEG quality and standalone audio bitrate independently in Settings. PNG optimization preserves pixels and transparency. Images are limited to 128 MB and 32 megapixels. APNG, HEIF, HDR images, ALAC, WAV, and MP3 are not supported. M4A requires one mono or stereo AAC track; unsupported metadata or layouts keep the original.

Hover over the notch to see a clock, Apple Music song information, artwork, and play/pause control. Choose Off, On hover, or Always for clock and music independently. Music access is requested when you connect.

## Frame rate

New settings preserve source frame timing, including variable frame rates. **Up to 30 fps** uses evenly spaced frames. Existing settings and queued tasks retain their previous behavior. Audio-only compression copies video unchanged.

See the [validation record (Japanese)](docs/VALIDATION.md) for tested environments and outstanding checks. Quality and size savings depend on the recording.

## Configure compression

Settings offers three presets and Custom. Custom sets video bitrate to 10–100% of the original in 1% steps, and audio bitrate to 32–256 kbps in 8 kbps steps. For example, 50% video bitrate and 80 kbps audio.

Changes are saved automatically and apply to newly added videos. Queued videos retain their settings; retrying uses the current settings. Video-only mode keeps audio unchanged, and audio-only mode keeps video unchanged.

A 50% video bitrate does not guarantee half the file size. If the original video bitrate is unknown, it is estimated from file size and duration. Custom video targets are bounded to 32 kbps–100 Mbps. Audio targets are capped at the original bitrate, with a minimum of 32 kbps.

| Preset | Ceiling used for automatic video bitrate | Audio target |
| --- | --- | --- |
| Higher quality | About 85% of original bitrate | AAC 128 kbps |
| Balanced | About 65% of original bitrate | AAC 96 kbps |
| Smaller files | About 45% of original bitrate | AAC 64 kbps |

The presets compare resolution × selected output fps × a coefficient (0.09, 0.06, or 0.035) with the original-bitrate ceiling, use the lower value, and bound it to 150 kbps–12 Mbps. These percentages are not file-size reduction targets.

All presets use the same codecs: hardware HEVC (H.265) for video and AAC for audio. Video resolution is preserved. Choose whether to preserve source frame timing or limit output to 30 fps. Unchanged tracks are copied without re-encoding. Custom replaces the automatic video calculation with the chosen percentage. Re-encoding is lossy; lost quality cannot be recovered.

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

Completed tasks leave the visible queue. The menu bar shows active, paused, or attention-needed counts. A completion summary shows before/after sizes and the difference for eight seconds, grouping consecutive completions. When output is not smaller, the result explains that the original was kept.

## Login, notifications, and background processing

Enable Launch at login in Settings to run the app after your next login. If macOS approval is needed, use Review Login Items. The queue window does not open automatically at login.

Notifications are enabled by default, but sending them requires permission in macOS. Completion notifications show measured before/after sizes; failures show recovery advice. Clicking a notification opens the queue. Video names and paths are excluded. Cancellation and restored history do not trigger notifications. Focus settings may hide banners; results remain available in the queue.

When space is low, choose **Use an external disk** in the queue. Disks are checked for available space before being offered, and you can choose another location. Temporary work and recovery records are removed on successful completion; no disk selection history is saved. Keep the external disk connected until work completes.

Low-space mode backs up the original to the external disk before returning the compressed result to its original location. After an interruption, the original location may be empty while the backup remains on the external disk. Connect that disk and recover from the queue; do not manually delete the backup folder. Recovery is separate from retrying an ordinary unfinished task.

Switching apps, closing the queue window, locking the screen, or turning off the display does not cancel compression. Active processing suppresses App Nap and idle sleep without preventing display sleep. The assertion is released when every task is paused or work finishes. System sleep pauses processing; waking removes only that sleep pause. Manually paused tasks stay paused. If the destination becomes inaccessible, the original is kept and recovery advice is shown. After logout, restart, or quitting, unfinished tasks must restart from the beginning. Quitting with unfinished work asks for confirmation and waits for cancellation.

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
