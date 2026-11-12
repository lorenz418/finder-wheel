# Finder Wheel: Design

Date: 2026-11-12
Status: approved in brainstorming, pending written-spec review

## Purpose

A macOS menu bar app that shows a gesture wheel over Finder, inspired by the SolidWorks mouse gesture wheel. It offers file actions that match the selected file types, so common jobs (merge PDFs, OCR to Markdown, convert, compress) no longer require external tools or uploading files to websites.

Guiding rule: the app must streamline work, not add clutter. Every wheel has few entries, and the same verb is always in the same direction.

## Constraints

- Native Swift / SwiftUI app. macOS 26 or later only (Liquid Glass material, on-device speech transcription).
- Apple frameworks only. The single exception is the Mistral OCR API. No bundled or required third-party tools (no ffmpeg, Ghostscript, LibreOffice, pandoc).
- Personal, locally built app. Not sandboxed, not distributed through the App Store.
- Must be fully usable with a trackpad.
- Originals are never modified or overwritten.

## Behaviour

### Summoning the wheel

1. The user selects files in Finder and holds the hotkey (default ⌥Space, configurable).
2. The wheel appears centred on the cursor. Its centre shows a selection summary, for example "3 images".
3. Moving the cursor into a wedge highlights it.
4. Releasing the hotkey runs the highlighted action. Releasing in the centre, or pressing Esc, cancels.
5. If Finder is not frontmost or nothing is selected, the hotkey does nothing.
6. If the selection contains no supported file type, the wheel appears briefly with a "no actions for this file" note.

### Wheel layout

Six fixed directions. Four verbs keep their direction on every wheel; the lower-left slot holds a type-specific extra; the bottom slot is unused in the first version. A verb that does not apply to the current type is not shown.

| Direction | PDF | Image | Video / audio |
|---|---|---|---|
| Up: Markdown | Mistral OCR to .md | Mistral OCR to .md | On-device transcript to .md |
| Upper right: Convert | Pages to PNG / JPG | JPG / PNG / HEIC / TIFF | MP4 / GIF / audio only (M4A) |
| Lower right: Compress | Light / medium / strong | Light / medium / strong, or resize to max width | Light / medium / strong |
| Lower left: Extra | Split into one file per page | Cut out (remove background, transparent PNG) | none |
| Upper left: Combine | Merge via reorder strip | Into one PDF via reorder strip | none |

Notes:

- WebP is accepted as an input image format but is not offered as an output (macOS cannot encode it natively).
- "Audio only" writes M4A (macOS cannot encode MP3 natively).
- For audio files, Convert offers only M4A, and GIF/MP4 are not shown.
- Native PDF compression works by downsampling and recompressing embedded images. It is effective on scanned and image-heavy PDFs and has little effect on text-only PDFs. This is an accepted limitation.

### Sub-options

- Releasing on a verb runs it with the last-used option for that file type. On first use, defaults apply: Convert image to JPG, Convert PDF to PNG, Convert video to MP4, Compress medium.
- Continuing to move outward past the wedge opens an outer ring with the alternatives; releasing on one runs it and stores it as the new last-used option.

### Mixed selections

Only verbs valid for every selected file are shown. A selection of PDFs and images offers Combine (into one PDF) and Markdown. A selection with no common verb is treated as unsupported.

### Reorder strip (Combine only)

After Combine is chosen, a slim panel appears at the cursor with one thumbnail per file, pre-sorted by filename in natural order (1, 2, 10). Return merges immediately; thumbnails can be dragged to reorder first; Esc cancels.

### Results

- Output is written next to the original with a suffix (for example `report-compressed.pdf`, `scan.md`, `photo.jpg`). Combine output is named after the first file with a `-merged` suffix.
- If the name already exists, a number is appended. Nothing is ever overwritten.
- When a job finishes, its outputs are selected in Finder.
- Image Convert and Compress strip location metadata by default; a settings toggle disables this.

### Progress and errors

- A menu bar icon is static when idle and fills as a progress ring while jobs run. Its menu lists running and recent jobs, with cancel for running ones.
- On failure the icon shows a warning dot and the menu lists the reason.
- A failure on one file does not stop the rest of a batch.
- Cancelling a job deletes any partially written output.
- Mistral: a missing key opens settings. Network and API errors are shown with the server's message. Before the first upload a one-time notice confirms that this action sends files to Mistral.
- If Finder automation permission is denied, the menu explains how to enable it in System Settings.

### Settings

One small window opened from the menu bar icon: hotkey, Mistral API key (stored in the Keychain), metadata-stripping toggle.

### Visual design

- Liquid Glass ring using the system material, so it adapts to light, dark and the content behind it.
- Six wedges with small gaps, each with an icon (SF Symbols) and a short label. The targeted wedge brightens. The outer ring uses the same material and fans out from the targeted wedge.
- Short, quiet appear and dismiss animations; nothing may delay the gesture.
- Reorder strip, menu and settings use the same material and standard system controls.

## Architecture

One menu bar app (no Dock icon) with five units.

| Unit | Responsibility | Depends on |
|---|---|---|
| Trigger | Registers the global hotkey; reports key down and key up; samples cursor position while held | System hotkey API |
| Selection reader | Reads the Finder selection; classifies it as PDF, image, video/audio, mixed or unsupported | Finder automation (Apple Events) |
| Wheel | Transparent floating panel that draws the wheel; pure geometry function maps cursor offset to wedge and ring; returns the chosen action and option | SwiftUI, layout table |
| Actions | One independent unit per action with a common interface: input files plus options in, output files or error out, progress reported along the way | PDFKit, ImageIO, Vision, AVFoundation, Speech, Mistral API |
| Job centre | Runs actions in the background; tracks progress and results; drives the menu bar icon; reveals outputs in Finder; handles cancel and cleanup | Swift concurrency |

Supporting pieces: the layout table (file type to verbs to sub-options, the single source of truth for what the wheel shows), the output-naming helper, the reorder strip panel, the settings window and Keychain access.

### Flow of one gesture

1. Trigger reports key down.
2. Selection reader returns the files and their classification.
3. Wheel looks up the layout table and displays the verbs.
4. On key up, Wheel reports the chosen action and option (or cancel) and closes.
5. For Combine, the reorder strip collects the final order.
6. Job centre runs the action, reports progress to the menu bar icon, and selects the outputs in Finder when done.

### Permissions

- Automation permission for Finder is required.
- The hold-hotkey is expected to work without Accessibility permission (system hotkey API for down/up, cursor position polling). This must be verified in the first build step; if it does not hold, Accessibility permission is requested with an explanation.

## Testing

Automated:

- Wheel geometry: cursor offset to wedge, centre dead zone, outer-ring threshold.
- Classification: single types, mixed selections, unsupported files.
- Layout table: each classification yields the expected verbs.
- Output naming: suffixes, collisions, Combine naming.
- Each action against small sample files (output exists, is valid, originals unchanged). Mistral is tested against a stubbed HTTP layer.

Manual checklist: gesture feel with mouse and trackpad, glass appearance in light and dark, permission prompts, menu bar progress, cancel.

## Build order

1. Trigger, selection reader, wheel, and one action (image Convert) end to end. Verify the permission assumption.
2. Remaining PDF and image actions, reorder strip.
3. Mistral OCR and settings.
4. Video and audio actions, transcription.
5. Visual polish: animation, icons, outer ring refinement.

## Out of scope for the first version

- Office and Markdown document conversion (needs non-native tools).
- PDF page-range extraction, rotate, password.
- Zip, copy path, batch rename (Finder already covers these).
- Open in Terminal or editor, and any wheel for an empty selection.
- User-customisable wheel layouts.
