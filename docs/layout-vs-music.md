# Layout versus Music

How NeoClub's Now Playing and Up Next layouts were calibrated to Music, what the vphone VM can and cannot tell you, and the numbers that are now in the code (`NowPlayingView.swift`).

Method (works well): dump Music's UIView frames (`layout.js`: UILabel / UIImageView / sliders / buttons converted to window coordinates) and NeoClub's drawn layers (`layout-neo.js`: leaf CALayers with contents, since SwiftUI draws no views), plus a full-resolution screenshot row scan (bright-pixel runs divided by the panel's height in points) for glyph positions.

**Caveat that cost a wrong turn: vertical positions from Music running in the VM are NOT the phone's.** Music's vertical layout depends on the safe-area insets, which differ between the VM and the phone; NeoClub's is anchored to the screen's edges. The owner's device-screenshot calibrations (the constants in `controls()`, `titleRow` padding, the header's top padding, landscape) are the truth for the phone. Evidence: inner portrait, VM Music minus the phone-calibrated NeoClub was +0.85 pt at the bottom row, +2.8 at the volume, +2.55 at the transport, +3.65 at the scrubber, +6.3 at the title and +11.9 at the artwork top (Up Next header: 41.8 in the VM, 32 on the phone), growing steadily upward like a different top inset. I retuned these to the VM once and then reverted. **Only use the VM for inset-independent things:** sizes and relative gaps inside one piece of UI, motion (card path, springs, timings), which view moves with what, which animations run, centring rules.

Inset-independent facts from Music (kept in the code):
- Up Next, outer screen: header artwork 72 pt; the buttons row sits 8.2 pt under it (37 pt high on the device; the VM said 38); the section header 21 pt under the buttons; queue rows 48 pt artwork on a 56 pt pitch. (NeoClub: speed and sleep capsules instead of Music's shuffle/repeat/infinity/clear; an extra "From ..." line under "Up Next" that Music doesn't have, which puts its first row about 12 pt lower.)
- Landscape with Up Next closed: Music centres the column on the **whole window** (artwork centre x 475.7 of 951); NeoClub's column was centred in the area left after the status-column inset (42 pt left). Fixed with an offset of (trailing inset minus leading inset) / 2 in artwork mode. With Up Next open Music's list is at x 507.7 (width 343.3, 16 pt in from the inset edge), its column title at x 52: this agrees with the owner's device numbers, so horizontal geometry in the VM matches the phone.
- Paused artwork is 330 pt base x 0.73 = 241 pt in landscape. (NeoClub's base was height-limited to 317 by the inset-reduced height; fixed on 2026-11-13 from the device screenshots: 330, capped by the full window height.)

If vertical positions need checking again, get a device screenshot of Music and NeoClub in the same state and compare in pt (3 px per pt on the Duo).

## Device calibration against Music, 2026-11-13 (the numbers now in the code)

The owner took the same states on the Duo in Music and NeoClub (outer, inner portrait, landscape; playing, Up Next, Info/Lyrics) with the text size set smaller. Method: put each pair side by side with a pixel ruler (`PIL`; no numpy was available), read positions in pt (2.951 px/pt on the outer screen, 2.103 on the inner screen), and find the scrubber and volume tracks by scanning one column for bright runs. Differences found, and what changed:

| State | Was | Now |
|---|---|---|
| Outer, Up Next | header artwork 51 pt from the top; speed/sleep capsules 44 pt tall (`SpeedButton` is 44 pt and `minHeight: 38` didn't cap it) | header 32 pt from the top (as Music, on both screens); capsules a fixed 37 pt; 8.4 pt under the header; panel 13.4 pt under them |
| Outer, playing | transport 3.7 pt high, times 1.8 pt high, bottom row 1.2 pt low | transport padding 1.9, volume padding 22.3, bottom-row padding 20.8, bottom padding 17.2; scrubber-to-times gap 5.8 (everywhere) |
| Inner portrait, playing | artwork 1.7 pt high, scrubber 1.4 pt low, bottom row 1.7 pt low | title padding 32.3, scrubber padding 18.5, bottom-row padding 34.7, bottom padding 17.7 |
| Landscape, playing | artwork 317 pt (capped by the inset-reduced height) instead of 330; whole column 8.6 pt high; title row 2.4 pt high | artwork 330 (cap from the full window height); column shifted down 8.6 pt (`.padding(.bottom, -8.6)`); scrubber padding 9.6 |
| Landscape, Up Next | list 3.8 pt low, then rows 1.9 pt low | panel top padding 14.3 |

After the changes every pair matched within about 1 pt (scrubber and volume tracks within 0.5 pt). Not compared: Info versus Lyrics panels (different content), laptop posture. Rows were compared with a real queue (56 pt pitch, 48 pt artwork on both).
