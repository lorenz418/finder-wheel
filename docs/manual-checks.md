# Manual checks

Run after every plan. Build and start with `scripts/build-app.sh && open "build/Finder Wheel.app"`.
After a rebuild macOS may ask again for permission to control Finder; allow it.

## Plan 1: foundation

Prepare a folder with: two PNG screenshots, one HEIC or JPG photo taken with location on, one PDF, one folder.

1. Select the two PNGs, hold ⌥Space. The glass wheel appears centred on the cursor; the centre reads "2 images".
2. Convert is upper right, Compress lower right, Cut out lower left, Combine upper left, Markdown up. The bottom wedge is dimmed and empty.
3. Slide to Convert: the wedge tints, and an outer ring with JPG, PNG, HEIC, TIFF appears.
4. Release on Convert: the wheel disappears at once; two JPG files appear next to the originals and are selected in Finder. The originals are unchanged.
5. Repeat and release on Convert again: two more files named `...-2.jpg` appear.
6. Hold, slide through Convert outward to HEIC, release: HEIC files appear. Hold again: the Convert wedge now shows "HEIC" as its small hint, and a plain release converts to HEIC.
7. Select a JPG and convert to JPG: no file appears; the menu bar menu lists the file as "Already JPG".
8. Convert the location-tagged photo to PNG or JPG. In Preview's inspector (⌘I) the result has no GPS tab.
9. Hold ⌥Space and press Esc: the wheel disappears and nothing runs. Release in the centre: nothing runs.
10. Select the folder, hold ⌥Space: all wedges are dimmed and the centre reads "No actions for this selection" for as long as the key is held.
11. Select nothing, press ⌥Space: nothing appears.
12. In another app (TextEdit), ⌥Space types a non-breaking space and no wheel appears.
13. With the trackpad only: hold ⌥Space with one hand, slide on the trackpad, release the key. Same results as with a mouse.
14. During a conversion of 20 or more images, the menu bar icon shows a progress ring; the menu lists the job with a Cancel button.
15. Appearance: check the wheel over a light window, a dark window and the desktop picture, in light and dark mode. Labels stay readable.
16. Flick quickly from the centre past the ring edge in the Convert direction. Note whether an outer-ring option is chosen by accident; if it happens often, raise `ringOuter` in `WheelMetrics` and re-run `swift test`.
17. Slots that are not implemented yet (everything except image Convert) report "This action is not available for this file" in the menu. This is expected until Plans 2 and 3.
18. Select a file whose icon is close to a screen edge and hold ⌥Space with the cursor on it. Part of the wheel is off-screen. Note which wedges cannot be reached and report this to the user; do not move the wheel away from the cursor without asking, because the gesture depends on the wheel being centred on it.
19. Hold on two images, slide straight out through Convert without curving: the outer-ring option straight ahead (PNG) is highlighted, not a border between two.

Added after the code reviews of Plan 1 (hand checks deferred from Tasks 9 and 10):

20. Permissions: the first ⌥Space in Finder asks "Finder Wheel wants access to control Finder"; allow it. No Accessibility or Input Monitoring prompt appears at any point. If the selection is never read, run `tccutil reset AppleEvents com.lorenz.finderwheel` and retry.
21. Release order: hold ⌥Space, release Option first and Space second; then the other way round. Each time the wheel closes once and acts once. Holding the keys for several seconds keeps the wheel open (no flicker).
22. After the wheel closes, Esc works normally in Finder again (for example it cancels a rename).
23. Hotkey conflicts: while renaming a file in Finder, ⌥Space opens the wheel instead of typing a non-breaking space. If you use more than one input source, note that ⌃Space (one of the alternative hotkeys) is the system shortcut for switching them. Decide whether the default hotkey suits you.
24. Glass details: the six wedges read as separate segments with small gaps, not one fused ring. In the menu bar icon, the warning dot (shown after a failed job) is distinguishable, and it clears each time the menu is opened, not only the first time.

## Plan 2: PDF, image and OCR actions

Prepare: a scanned or image-heavy PDF of several pages, a text-only PDF, a password-protected PDF, a PDF with a sideways page, a photo of a person or object, a PNG screenshot with text, and a valid Mistral API key.

1. Image Compress, medium on a JPG photo: `photo-compressed.jpg` appears and is smaller. On a PNG screenshot: `shot-compressed.jpg`.
2. Image Compress, outer ring "2000 px" on a large photo: the result's longest side is 2000 px.
3. Cut out on the photo of a person: `photo-cutout.png` has a transparent background (check in Preview). On a blank screenshot: the menu lists "No subject found in this image".
4. PDF Convert (PNG): a folder `name-pages` appears and is selected; it holds one sharp PNG per page. The sideways page is rendered sideways, not clipped.
5. PDF Convert, outer ring JPG: same with JPG files, in `name-pages-2`.
6. PDF Split: a folder with one-page PDFs named `name-p01.pdf` and so on.
7. PDF Compress, strong on the scanned PDF: clearly smaller, still readable. On the text-only PDF: the menu lists "Already as small as it gets" and no file appears.
8. Any PDF action on the password-protected PDF: the menu lists "PDF is password-protected" and the menu bar icon shows the warning dot until the menu is opened.
9. One PDF selected: the Combine wedge is dimmed. One image selected: Combine produces a one-page PDF.
10. Combine three phone photos: strip appears sorted by name; Return writes `first-merged.pdf`. In Preview the pages are A4-sized (portrait or landscape to match each photo) and sharp when zoomed in.
11. One PDF plus two images selected: the wheel shows only Markdown, Compress and Combine; Convert and the lower-left wedge are dimmed. Combine merges all three into one PDF. Compress writes a `-compressed` file for each.
12. Remove the API key in settings. Markdown on a PDF: the settings window opens, shows "Add a key to use Markdown on PDFs and images.", and nothing is uploaded.
13. Enter the key and click Save. Markdown on the scanned PDF: the one-time "Send files to Mistral?" notice appears in front of Finder; Cancel uploads nothing and ⌥Space works again straight away. Run again, Continue: `name.md` appears with the recognised text. Run once more: no notice.
14. Markdown on the PNG screenshot and on a HEIC photo of a document: an `.md` file with the text for each.
15. Enter a wrong key, run Markdown: the menu lists a Mistral error with the HTTP status; no file appears.
16. Turn Wi-Fi off, run Markdown: the menu lists "Could not reach Mistral: ...".
17. Start PDF Convert on a PDF with 100 or more pages and press Cancel in the menu: the job shows "Cancelled" and no `-pages` folder is left behind.

Added after the code reviews of Plan 2 (hand checks deferred from Tasks 7 and 8):

18. Reorder strip: Finder's window stays active while the strip is open; dragging a thumbnail onto another reorders them and the strip stays open; Esc cancels; ⌥Space does nothing while the strip is open; clicking into Finder closes the strip without combining.
19. Settings: "Settings…" opens the window in front. Changing the hotkey to ⌃ Space makes ⌥Space stop working in Finder and ⌃Space work; change it back. A saved key survives quitting and relaunching (after a rebuild macOS may ask for your login password to read it).
20. Turn off "Remove location data", convert a location-tagged photo: the result keeps its GPS data. Turn it back on.
21. A PDF cropped in Preview (Tools > Crop) converts to images showing only the cropped area.
