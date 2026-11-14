# Changelog

## 1.2 (build 261113.3)

### New
- **Release dates** at the bottom of episode and album pages, in the same muted style as the episode number and length. Albums take theirs from one of their episodes, falling back to the album's copyright year.
- **Album name on the artist line.** Now Playing, the lock screen, Control Center and CarPlay show the album's number and name (for example "#83: Phase One") instead of "Adventures in Odyssey". The album is looked up from the library, so it is right wherever playback started, including episodes of an album that isn't fully released yet.
- **Debug menu.** "Sync Listening Progress" and "Show Downloads in Files" moved out of Account into a menu opened by holding the profile picture on Home.

### Improved
- **Scrubber and volume slider** now follow Music's touch behavior, traced from Music itself: the bar grows from 7 to 16 pt, the whole control scales to 105%, the times light up, and the springs match. Dragging is relative to where you touched, ignores the first 8 pt of finger movement, and the volume's speaker icons shift when you push past either end.
- **Progress bars** have a straight right edge on the played part, like Music's.
- **Search** has a Liquid Glass field that always looks like the system's active one and stays at the top of the page.
- **Launch** shows a navy launch screen and restores the mini player before the first frame, to avoid the flash and the layout moving in from a corner.

### Fixed
- Now Playing shows paused, with the smaller artwork and a play button, when another app takes the audio.
- Duo outer screen: the regular-phone Now Playing layout was being chosen from the inset-reduced width and spreading the controls out. It now uses the full window width, and other iPhones are unchanged.
- The CarPlay volume slider keeps its dimmed track, like Music's.
