# Next release notes — unpublished draft

[日本語](next.ja.md)

These notes describe development work. The version and download links will be finalized after distribution checks. Alpha.2 remains the currently published version.

- Keep the original and complete normally when compression does not reduce file size. Notifications and results explain that no reduction was made.
- Track system-sleep pauses separately from manual pauses. Waking the Mac does not resume tasks you paused manually.
- Choose between preserving source frame timing and limiting output to 30 fps. New settings preserve source timing; existing settings and queued tasks keep their previous behavior.
- Support Japanese and English across normal operations, notifications, failure explanations, and restored history. Original technical logs and file names are not translated.
- Provide separate Japanese and English DMG instructions. Both contain the same app, whose interface follows the macOS language preference.

Hardware HEVC remains the default. No new codec or speed preference is being made the default before representative screen recordings have been evaluated. Non-video compression is outside this release.

## Checks remaining before publication

Actual sleep/wake during encoding and validation, and automatic Sparkle update/relaunch from the fixed build have passed. Build 10 app and both DMGs are signed and notarized. The language-switch fix and a single-video Finder drop onto the center notch target have also passed. Remaining checks cover notification banners, launch after login, representative recording quality. Anonymous downloads will be verified after publication.

In alpha.2, an open settings sheet can prevent update relaunch. This release fixes that behavior; the verified workaround for the old version is to close Settings and quit from the app menu, after which installation finishes and the app relaunches. This is also documented in the README.

## Saving files

Smaller output replaces the original only after full output validation. The uncompressed original is no longer available after replacement. Failure, cancellation, or no size reduction keeps the original.
