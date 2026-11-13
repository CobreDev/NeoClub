You're picking up NeoClub (/Users/cobre/Developer/NeoClub), a native SwiftUI replacement for the Adventures in Odyssey Club app, which runs on my iPhone Duo. Every screen should behave exactly like Apple Music on iOS 27, while keeping the AIO Club look.

Start by reading docs/HANDOFF.md, then docs/original-app-analysis.md. They cover:
- the goal and the hard rules: account safety, test playback only on Whit's Flop, native components, how to use vphone
- the code map
- exactly how Now Playing's open and close work (traced from Music with Frida) and how its layout was calibrated against my device screenshots
- the release process: date-based build numbers (`YYMMDD`, tagged `build-<number>`), `scripts/make-release.sh`, and the debug tools that were removed from `main` and kept at the `debug-harness` tag

Where things stand: the Now Playing animations are signed off, the layout matches Music within about a point on both screens, debug code is removed, and the app opens on Home after a fresh launch. The next step is the release build and my check of it on the Duo.

When something should match Music:
- Measure it: trace Music in the vphone VM with Frida, or compare my screenshots and recordings side by side.
- Copy the mechanism Music actually uses.
- Don't eyeball it or hand-build an imitation.
- The VM can't settle vertical positions (its safe-area insets differ from the phone's); use my device screenshots for those.

Ask before any write to my account, and don't play or seek any episode other than #001 Whit's Flop. Don't push. Commit when a piece of work is finished.
