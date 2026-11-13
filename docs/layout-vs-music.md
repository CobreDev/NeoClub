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

## Regular iPhones (iPhone 18 Pro, 402 x 874 pt), 2026-11-13

The Duo constants above are calibrated for the Duo's 678 pt outer screen, where the fixed gaps bunch the controls near the bottom. On a taller regular iPhone Music spreads them out, so `portraitLayout` has a `regularPhone` branch (`size.width < 450`; the Duo's outer screen is 466 wide, so it keeps its own numbers).

The test is on the whole window (`size.width + insets.leading + insets.trailing < 450`), not `size.width` alone: the Duo's outer screen puts its status column on the right, whose ~85 pt trailing inset leaves the player ~380 pt wide, so the width alone took the Duo's outer screen for a regular phone (fixed 2026-11-13; the controls had spread out and the artwork shrunk). Any new width test must allow for the insets.

Reference: Music in a vphone VM created as an iPhone 18 Pro (`--device iPhone19,2`, iOS 27.2, screenConfig 1206x2622), which reports the real safe-area insets (62 top, 34 bottom), so unlike the Duo VM its vertical positions are trustworthy. Method: `frida/layout.js` on Music (UIView frames in window points) against `frida/layout-neo.js` on NeoClub (drawn layers), Music paused. Positions, window points:

| Element | Music | NeoClub before | Now |
|---|---|---|---|
| Artwork (playing) | 354 wide at x 24, y 95 | 338 wide, under the title | 354 (`content + 16`, -8 padding each side) |
| Artwork (paused, 0.73) | 258.7, y 142.7 to 401.4 | y 268 to 515 | y 143.5 to 402 |
| Title text centre | 505 | 596 | 505.5 (title padding 42.3) |
| Time labels centre | 598 | 676 | 597.9 (scrubber padding 24) |
| Transport centre | 666.3 (skip buttons at x 95 and 307) | 713 | 666.3 (padding 33.2; side padding 45) |
| Volume centre | 756.3 | 774 | 756.3 (padding 51.3) |
| Bottom icons centre | 808.5 (x 87, 201, 315) | 824, x 52 and 350 | 808.7, x 86.7, 200.8, 314.7 (bottom padding 33, 35 pt side inset) |
| Grabber centre | y 71 (7 under the safe area) | 21 | 71 |
| Up Next header artwork | 72 pt at y 95 | y 68 | y 95 |
| Up Next button row | y 182, 38 high, 15 under the artwork | 8.4 under, 37 high | 15 under, 38 high |

Up Next's list: Music's first row is at y 280.3; NeoClub's is 9.7 lower, the "From ..." line kept on purpose.

**Mode capsules.** Music's row is four equal capsules (shuffle, repeat, infinity, clear): 74.7 pt wide, 13 pt apart on the phone (about 73 wide and 15 apart on the Duo's outer screen). Speed and sleep timer are two capsules with the same 13 pt gap that together fill the same width as Music's four (162.5 pt each on a 402 pt phone).

Not compared on the phone: Info versus Lyrics, landscape (the 18 Pro in landscape), the laptop posture (Duo only).
