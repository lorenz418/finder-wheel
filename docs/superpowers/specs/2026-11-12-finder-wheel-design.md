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
5. The hotkey is registered only while Finder is frontmost, so in every other app the keystroke passes through untouched. In Finder with nothing selected, the hotkey does nothing.
6. If the selection is unsupported (see "Selection classification"), the wheel appears briefly with a "no actions for this selection" note.

### Selection classification

The selection reader returns exactly one of:

| Classification | Condition |
|---|---|
| PDF | Every item is a PDF |
| Image | Every item is an image (JPG, PNG, HEIC, TIFF, WebP). GIF files are unsupported as input |
| Video | Every item is a video |
| Audio | Every item is an audio file |
| Video + audio | Videos and audio files only |
| PDF + image | PDFs and images only |
| Unsupported | Anything else: any folder, any other file type, or any other mix |

A single unsupported item makes the whole selection unsupported. Nothing is silently skipped. Types are decided by the system's uniform type identifiers (conformance to PDF, image, movie, audio), not by file extension.

The "no actions" note is shown for as long as the hotkey is held. In Finder with nothing selected, the keystroke is consumed and nothing is shown.

### Wheel layout

Six fixed directions. Four verbs keep their direction on every wheel; the lower-left slot holds a type-specific extra; the bottom slot is unused in the first version. The ring is always drawn whole with six wedges: a slot with no action for the current selection is drawn as a dimmed, unlabelled wedge that cannot be targeted (releasing on it cancels).

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
- For audio files, Convert offers only M4A, and GIF/MP4 are not shown. - In every Convert, a file that is already in the target format is skipped and listed as skipped in the menu.
- Combine is dimmed when a single PDF is selected. A single image can still be combined into a one-page PDF.
- Markdown always writes one .md per input file.
- Transcription uses the language chosen in settings (default: the system language). If the on-device model for that language is not installed, the job reports this in the menu and offers to download it.
- Native PDF compression works by downsampling and recompressing embedded images. It is effective on scanned and image-heavy PDFs and has little effect on text-only PDFs. This is an accepted limitation.

### Sub-options

- Releasing on a verb runs it with the last-used option for that file type. On first use, defaults apply: Convert image to JPG, Convert PDF to PNG, Convert video to MP4, Compress medium.
- Continuing to move outward past the wedge opens an outer ring with the alternatives; releasing on one runs it and stores it as the new last-used option.

Starting values for presets (to be tuned during the build, not user-configurable in the first version):

| Preset | Value |
|---|---|
| Image Compress light / medium / strong | Lossy quality 0.8 / 0.6 / 0.4. JPG and HEIC inputs keep their format. PNG, TIFF and WebP inputs are written as JPG, with any transparency flattened onto white |
| Audio Compress light / medium / strong | Re-encoded as M4A (AAC) at 192 / 128 / 96 kbps, whatever the input format |
| Image Compress "resize" | Fourth outer-ring option: longest side 2000 px, medium quality |
| PDF Compress light / medium / strong | Embedded images downsampled to 200 / 150 / 100 dpi |
| Video Compress light / medium / strong | 1080p / 720p / 540p H.264 system export presets |
| PDF to PNG / JPG | 200 dpi |
| Video to GIF | 480 px wide, 12 frames per second |

### Mixed selections

Two mixes are supported; each is its own entry in the layout-table data structure. In a video + audio mix, Compress applies the video preset to videos and the audio preset to audio files.

| Mix | Verbs shown |
|---|---|
| PDF + image | Markdown (Mistral OCR, one .md per file), Compress, Combine (into one PDF). Convert and Extra are dimmed. |
| Video + audio | Markdown (transcript per file), Compress, Convert with M4A as the only option. |

For Compress on a mix, the outer ring offers light / medium / strong only. Releasing on the verb uses medium; mixes do not read or store last-used options.

### Reorder strip (Combine only)

After Combine is chosen, a slim panel appears at the cursor with one thumbnail per file, pre-sorted by filename in natural order (1, 2, 10). Return merges immediately; thumbnails can be dragged to reorder first; Esc cancels.

### Results

- Output is written next to the original with a suffix (for example `report-compressed.pdf`, `scan.md`, `photo.jpg`). Combine output is named after the first file with a `-merged` suffix.
- Actions that produce many files from one input (PDF Split, PDF to PNG / JPG) write them into a new folder next to the original, named after it (for example `report-pages/report-p01.pdf`).
- If the name already exists, a number is appended. Nothing is ever overwritten.
- When a job finishes, its outputs are selected in Finder. For folder outputs, the folder is selected.
- Image Convert and Compress strip location metadata by default; a settings toggle disables this.

### Progress and errors

- A menu bar icon is static when idle and fills as a progress ring while jobs run. Its menu lists running and recent jobs, with cancel for running ones.
- On failure the icon shows a warning dot and the menu lists the reason.
- A failure on one file does not stop the rest of a batch.
- Cancelling a job deletes any partially written output.
- Mistral: a missing key opens settings. Network and API errors are shown with the server's message. Before the first upload a one-time notice confirms that this action sends files to Mistral.
- If Finder automation permission is denied, the menu explains how to enable it in System Settings.

### Settings

One small window opened from the menu bar icon: hotkey, Mistral API key (stored in the Keychain), transcription language, metadata-stripping toggle.

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
| Selection reader | Reads the Finder selection; returns one of the seven classifications in "Selection classification" | Finder automation (Apple Events) |
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
- The hold-hotkey is expected to work without Accessibility permission (system hotkey API for down/up, cursor position polling). The same check covers catching Esc while the hotkey is held and registering the hotkey only while Finder is frontmost. This must be verified in the first build step; if it does not hold, Accessibility permission is requested with an explanation.

## Testing

Automated:

- Wheel geometry: cursor offset to wedge, centre dead zone, outer-ring threshold.
- Classification: single types, mixed selections, unsupported files.
- Layout table: each classification yields the expected verbs.
- Output naming: suffixes, collisions, Combine naming.
- Each action against small sample files (output exists, is valid, originals unchanged). Mistral is tested against a stubbed HTTP layer.

Manual checklist: gesture feel with mouse and trackpad, glass appearance in light and dark, permission prompts, menu bar progress, cancel.

## Build order

1. Trigger, selection reader, wheel, job centre with the menu bar icon, and one action (image Convert) end to end. Verify the permission assumption.
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
