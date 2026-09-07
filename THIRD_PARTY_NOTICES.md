# Third-party software

NotchCompressor source code is licensed under Apache-2.0. That license does not replace the licenses of the following separate executables.

## FFmpeg 9.0.1

Copyright (c) the FFmpeg developers. https://ffmpeg.org/

The app invokes bundled `ffmpeg` and `ffprobe` as separate processes. They are built from unmodified FFmpeg 9.0.1 source, with GPL and nonfree components disabled, under the GNU Lesser General Public License, version 2.1 or later (LGPL-2.1-or-later). The license and upstream LICENSE.md are included in the app's Resources/Licenses folder. This software comes without warranty; see the license for details.

Corresponding source: `ffmpeg-9.0.1.tar.xz`, distributed alongside the application in the same GitHub Release. Upstream source: https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz

SHA-256: `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635`

Build instructions: run `bash scripts/build-ffmpeg.sh` on macOS with Xcode 26 or later. The script records all configure arguments and pins the source checksum. No patches are applied. Generated config.h and `ffmpeg -buildconf` are included in the release's build-information archive. External libraries are not auto-detected; only macOS system frameworks/libraries are dynamically linked. Users may rebuild and replace these executables in Contents/MacOS and re-sign their local app with an ad hoc signature. No restriction is imposed on modifying or reverse engineering these components for debugging modifications.

For future updates, change the version and checksum together after verifying the upstream release signature, then rebuild, inspect dynamic dependencies, and run the full media integration suite before publishing a new app and matching source archive.
