# Stationary landing-page demo

2026-11-25: user requested a stationary, proportionate Mac demo, relevant feature icons, and an actual queue screenshot instead of FAQ blocks. LP publication remains authorized; this does not publish the draft app release or Sparkle feed.

- Removed scroll-driven scale, translation, scene switching and sticky tracking from `site.js`.
- Reused the existing Mac reference dimensions documented in `style.css`: a 1380-wide display and 168 × 30 notch. Expanded demo uses the native `NotchGeometry` panel width of 480 and height of 30 + 148. Hit testing uses the same dimensions, independent of animation progress.
- Above 600 CSS pixels, show the complete Mac. At 600 and below, crop a fixed 680-pixel desktop around its center; explain the crop beneath the demo. This preserves usable drop targets without enlarging the notch relative to the underlying desktop. Drag, tap and keyboard alternatives remain available.
- Feature icons now depict stacked files/addition, a media processor, background processing and language support.
- Replaced FAQ with a real build 11 queue screenshot and inline explanations of formats, replacement, quality, sleep and installation. The screenshot uses test fixtures; the Japanese page explicitly identifies the English UI screenshot. The image opens at full size.
- Main still links to the public alpha.2 preview and identifies feature descriptions as upcoming 0.1.0. Do not overwrite these links with the unpublished DMG links in draft PR #39 before the app release is published.

Validation: JS syntax and whitespace checks; browser rendering at 375 × 812, 768 × 1024 and 1280 × 900; no horizontal overflow; all images loaded; Japanese center/video drop and pause, English audio selection; light and dark appearance. These viewport checks are not a physical iPad Safari touch acceptance test.
