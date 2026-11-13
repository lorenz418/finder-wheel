# Finder Wheel

A gesture wheel for Finder. Select files, hold ⌥Space, flick toward an action, release.

Runs on macOS 26 or later. Everything happens on your Mac except Markdown for PDFs and images, which uses the Mistral OCR API.

## Build and run

    scripts/build-app.sh
    open "build/Finder Wheel.app"

Requires Xcode 27 or later. The app lives in the menu bar; there is no Dock icon.

On first use macOS asks whether Finder Wheel may control Finder. Allow it: this is how the app reads which files are selected. Because the app is signed ad hoc, macOS asks again after each rebuild. To avoid that, sign with a development certificate:

    SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh

To start it at login, add the app under System Settings, General, Login Items.

## Actions

| Direction | PDF | Image | Video / audio |
|---|---|---|---|
| Up: Markdown | Mistral OCR | Mistral OCR | On-device transcript |
| Upper right: Convert | PNG, JPG (one image per page) | JPG, PNG, HEIC, TIFF | MP4, GIF, M4A |
| Lower right: Compress | Light, medium, strong | Light, medium, strong, 2000 px | Light, medium, strong |
| Lower left | Split into pages | Cut out the subject | |
| Upper left: Combine | Merge into one PDF | Into one PDF | |

Releasing on a wedge repeats your last choice. Sliding further out shows the alternatives.

Originals are never changed. Results appear next to them and are selected in Finder.

Convert to MP4 re-wraps the video without re-encoding when it is MP4-compatible (keeps HEVC and HDR, near-instant); otherwise it re-encodes.

## Settings

Menu bar icon, then Settings: hotkey, Mistral API key (stored in the Keychain), transcription language, and whether location data is removed from images.

## Known limitations

- PDF Compress shrinks scanned and image-heavy PDFs; text-only PDFs are reported as "Already as small as it gets". It may lower the quality of already-low-resolution scans (like Preview's Reduce File Size).
- Video Compress produces H.264 and converts HDR to SDR. For iPhone HEVC clips the light preset is often not smaller and is reported as "Already as small as it gets".
- Video to GIF converts the whole video. Trim long videos first. Videos narrower than 480 px keep their width.
- Markdown from Mistral keeps image references as plain links; the images themselves are not saved.
- WebP and GIF cannot be written. GIF files are not accepted as input.

## Development

    swift test

If the repository is inside an iCloud-synced folder (Desktop, Documents), `swift build` and `swift test` fail at code signing. Point them at a build folder outside it:

    swift test --scratch-path /tmp/finder-wheel-build

Logic and file actions are in `Sources/FinderWheelCore` and covered by tests. The app shell is in `Sources/FinderWheel`. Manual checks are in `docs/manual-checks.md`. The design is in `docs/superpowers/specs/2026-11-12-finder-wheel-design.md`.
