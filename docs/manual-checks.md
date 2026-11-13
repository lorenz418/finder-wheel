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
