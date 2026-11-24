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

Verify both interface languages and dependency dialogs, actual Mac sleep/wake, Finder drops, notifications, login launch, and a Sparkle update from alpha.2. Sign, notarize, and verify downloads of the new release artifacts. Outstanding checks must not be presented as completed.

## Saving files

Smaller output replaces the original only after full output validation. The uncompressed original is no longer available after replacement. Failure, cancellation, or no size reduction keeps the original.
