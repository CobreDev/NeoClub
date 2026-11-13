# NeoClub handoff

Last updated 2026-11-13. `main` is the source of truth (`git log`). Releases are tagged `build-<number>` on the commit they were built from; the debug tooling that was removed before release is kept at the tag `debug-harness` (see "Debug tools" below). The repo is private at https://github.com/CobreDev/NeoClub (`origin`); `main` and the tags were pushed on 2026-11-13 at the owner's request. Don't push again unless asked.

## Goal

NeoClub is a native SwiftUI replacement for the official **Adventures in Odyssey Club** app, which is built in Flutter and is clunky. It's for the owner's own use on an **iPhone Duo** (foldable). It's installed directly from Xcode and through the owner's private AltStore source.

The bar for every screen is **"behaves exactly like Apple Music"** (iOS 27): layout, gestures, springs, sheet presentation and Liquid Glass. The visual identity stays AIO Club: Jacoby and Univers fonts, AIO blue, honeycomb backgrounds, official art and the official icon. Users see the name "AIO Club"; "NeoClub" is only the project name.

When matching Music, the method that works is to **measure Music, not guess**:
- trace the real Music app with Frida in the vphone VM
- step through the owner's screen recordings frame by frame

Copy the mechanism Music actually uses (often a private UIKit setting) rather than imitating the look by hand.

## Current state

- Version **1.0**, bundle ID `dev.cobre.aioclub`, team `4BN7V65X8J`, iOS 26.2+, XcodeGen (`project.yml`).
- **Build numbers are dates**: `YYMMDD` (`261113` = 13 Nov 2026), then `261113.2`, `261113.3` for more builds the same day, so they always increase and read as a date. `scripts/make-release.sh` sets them and tags the commit `build-<number>` (`git show build-261113`). The short commit hash is baked into the app too (`NeoClubCommit` in Info.plist) and shown in Account's footer: "AIO Club 1.0 (261113 · 4a02eeb)". Dev builds from Xcode are build `0` / commit `dev`.
- v1 scope is done:
  - sign-in (OAuth, the official client ID), profiles with PINs
  - Home, Browse, Library, Search, episode and album pages
  - player with background audio, lock screen, Up Next (Play Next and Play Last), progress sync
  - downloads (background session), bookmarks
  - Dynamic Type
  - outer and inner Duo layouts, including laptop posture and split view
- 13 unit tests in `NeoClubTests` pass.
- **Now Playing animations are signed off by the owner** (open, tap close, drag close, flick close, reopen), and the layout was matched to the owner's device screenshots of Music on 2026-11-13 (see the layout section).
- **Release prep (2026-11-13):** all debug code is removed from the app (launch arguments, the NP state log, the API log, the sign-in log, the placeholder UI-only mode, the Debug menu and API Explorer, the 10-second sleep timer). The two switches the Debug menu held that are real settings, *Sync Listening Progress* and *Show Downloads in Files*, are now in Account.
- **Launch behaviour:** the app opens on Home after a fresh launch. The tab and pages are remembered only for the life of the process (`SceneMemory` in `MainTabView`), so unfolding the Duo (which recreates the window) keeps your place, but quitting and relaunching does not. (It used to restore the last pages from `@SceneStorage`, rebuilding an album from a bare ID, which showed a black rectangle where its header should be.) The mini player still brings back the last episode, paused.

## Hard rules (owner's instructions)

1. **Account safety.** The real paid AIO account is used. Mirror the official client's requests: headers `X-Experience-Name`, `X-VIEWER-ID`, `X-PIN` and the same OAuth parameters. Keep API probing to a few spaced-out read-only GETs. **Ask before any write**: progress, ratings, profile or PIN, membership. Never type the owner's password or PIN; they sign in themselves.
2. **Progress safety.** Sync is ON in normal builds (switch in Account).
   - Test playback only on **#001 Whit's Flop** (`a354W0000046TjUQAU`, Cooper profile). Use the Cooper profile for everything.
   - Never play, seek or mark played any other episode, and never overwrite episodes that are in progress or the owner's place in an album, without asking. (Once the app is built, moving progress backwards is fine, but not by testing on real progress.)
   - Restoring Whit's Flop to Complete at 1301240 used `-debugRestoreTestEpisode`, which is no longer in the app; build the `debug-harness` tag for it (see "Debug tools").
   - Simulator testing without writes: `-syncProgress NO` still works (it is read from `UserDefaults`, so a launch argument sets it), or build the `debug-harness` tag's placeholder mode.
   - VM builds signed in to the real account must use `-DFORCE_NO_SYNC` (kept in `ProgressSync`: `isEnabled` is always false under it).
   - Ignore the episodes that were finished locally while sync was off. Never push them.
3. **Native components.** Use system bars, blurs, menus, sheets and glass. No hand-drawn imitations.
4. **Duo inner screen.** Full-width single-page browsing. No list/detail two-pane split.
5. **vphone.** Use it as designed. Don't edit the VM's `config.plist` screen config. Change the fold with `display.posture`. Don't change host security settings, SIP or boot-args.
6. Commit only when asked or when finishing agreed work. Push only when asked (the private repo `CobreDev/NeoClub` exists as `origin`). `dist/` is gitignored.

## Architecture map

| Area | Files |
|---|---|
| App, root, phases | `NeoClub/App/NeoClubApp.swift` (AppModel: loading → signedOut → choosingProfile → ready) |
| API | `NeoClub/API/APIClient.swift`, `AIOService.swift`, `Models.swift`; response cache for offline use |
| Auth | `NeoClub/Auth/*` (OAuth, Keychain) |
| Tabs, mini player, Now Playing host | `NeoClub/Features/MainTabView.swift` (`MiniPlayer`, `NowPlayingPresentation`, `WindowInsetsProbe`) |
| Now Playing UI | `NeoClub/Player/NowPlayingView.swift` (outer, inner portrait and landscape, laptop layouts), `NowPlayingControls.swift`, `NowPlayingPanels.swift` (Up Next, Info, backdrop) |
| Presentation (open and close) | `NeoClub/Player/NowPlayingPresenter.swift` |
| Playback, queue, sync | `NeoClub/Player/AudioPlayer.swift` (`addedCount` = Music's "Playing Next"; `queueNext`, `queueLast`), `ProgressSync.swift` (`isEnabled`; always false under `FORCE_NO_SYNC`) |
| Theme and fonts | `NeoClub/App/Theme.swift` (`Font.univers`, `universBold`, `jacoby` scale with the text style nearest each size) |
| Row swipes, context menus | `NeoClub/Features/Components.swift` (`.episodeSwipeActions`) |
| Account | `NeoClub/Features/Profiles/AccountView.swift`: profile, switch profile, *Sync Listening Progress*, *Show Downloads in Files*, sign out, version footer (`NeoClub/App/AppVersion.swift`) |
| Launch state | `MainTabView.SceneMemory`: tab and navigation paths kept in memory for the process only |
| Research notes | `docs/original-app-analysis.md` (the original app's API notes, Music's Now Playing traces) |
| Release | `scripts/make-release.sh` (needs a clean, committed tree) builds `dist/NeoClub-<version>-<build>.ipa`, tags `build-<build>`, and prints the version, build, date, size and minimum OS for the owner's existing AltStore source. **Don't generate a source.json**: the owner already has a source. |

## Now Playing: how it works now (from tracing Music)

This is where most of the effort has gone.

**Presentation.** A full-screen form sheet, like Music's.
- `modalPresentationStyle = .formSheet`, `detents = [.large()]`, no grabber.
- Private settings, set by KVC, guarded with `responds(to:)`:
  - `_wantsFullScreen = YES`
  - `_allowsInteractiveDismissWhenFullScreen = YES` (without it the sheet's drag recognizer stays disabled)
  - `_cornerRadiusForPresentationAndDismissal = 24`
- Sheet source = the bar's content view (`SwiftUI.UIKitTabBarBottomAccessory`, the first subview of `_UITabAccessoryContainer`). Set both the public `sourceView` and the private `-[_UISheetPresentationController _setSourceView:]`.

**Open.** UIKit's own sheet animator, as in Music (traced 2026-11-12: Music's `PalettePresentationAnimationController` sets only `sourceFrame` = the bar's frame): `animationController(forPresented:)` returns `_UISheetAnimationController` with `sourceFrame` set (`sheetAnimator(reversed:)`), so the card grows out of the bar with the bar's glass matched to it. The player stays pinned top-left and is revealed, and a copy of the artwork grows from the bar's artwork slot to its place on the same spring (`prepareOpenArtwork` / `startOpenArtwork`). Gotchas: create that copy with `UIImageView(frame:)` (not `init(image:)`) and add it inside `performWithoutAnimation`, or the transition's animation context animates it in from the image's natural size. The old hand-built `OpenAnimator` (spring card with glass fading off the player, flat 12% dim) stays only as a fallback.

**Close.** `animationController(forDismissed:)` returns UIKit's private `_UISheetAnimationController` with `isReversed = YES` and `sourceFrame` = the bar's frame in the window. This is exactly what Music's `PalettePresentationAnimationController` subclass sets. UIKit does the rest:
- On release, the card shrinks to the bar's size where it is, then springs into the bar, keeping the flick's velocity.
- The bar's glass follows the card through `CAMatchPropertyAnimation`s.

Without `sourceFrame`, the card slides off the bottom of the screen.

**Drag.** The sheet's own pan (`_UISheetInteraction`), as in Music. The old hand-made `PresentedCard` pan is gone. Don't reapply detents while a drag is in progress: it made the sheet spring back instead of closing.

**Close, as measured on Music with Frida** (presentation-layer geometry of every view in the card, sampled through a close; `sample.js` style script, see recipes).
- The card (UIKit's sheet animation) shrinks to the bar on mass 1 / stiffness 333.33 / damping 36.51. NeoClub's card path matches Music's: at card widths 389 / 351 / 301 pt the heights are 403 / 266 / 86 in both.
- **Music's player content is never scaled or moved inside the card.** The title stays 266 pt wide and about 396 pt below the card's top edge, the scrubber 350 pt, the play button 32 pt, for the whole close. The card just clips it as it shrinks. Nothing rides up with the bottom edge. (An earlier version of this code used top and bottom snapshot stand-ins that did ride up; that was wrong.) So the real player stays laid out at the window's size pinned top-leading (`NowPlayingPresentation`) and the card clips it.
- The player fades out (`MusicCoreUI.PassthroughView` / lyrics background opacity 1 to 0 over 0.7153 s, cubic (0.1878, 0.0023, 0.5399, 0.9629)).
- The grabber is a keyframe animation: opacity 1, 0, 0 at key times 0, 0.5, 1 over 0.5 s on the default curve (0.25, 0.1, 0.25, 1), so it's gone after 0.25 s.
- The bar's own content view fades 0 to 1 over 0.5 s on the default curve. Only the content: fading the accessory view also fades the glass in from nothing (a black pill).
- The card's own background (`UIDropShadowView`, opaque black in the app's dark appearance) is animated to clear on the card's spring. Without it a black pill sits over the bar after the card lands.
- The artwork is the only thing that travels: its bounds shrink by about 210 pt on the card's spring, corner radius 10 to 5.5 in Music's bar (6 in ours), landing in the bar's artwork slot (Music: (16, 9, 30, 30) in the bar; NeoClub: (14, 8, 32, 32)). Our copy of the artwork lands exactly on the card's progress (at card progress 0.436 it is 145.3 pt; interpolating linearly predicts 145.3).

**Fixed layout.** `NowPlayingPresentation` lays the player out at the window's size, pinned top-leading, in the named coordinate space `nowPlaying` (this is what lets the card clip it like Music's). It must be an `overlay(alignment: .topLeading)` on a `Color.clear` base: a fixed-size frame inside a flexible `.frame(maxWidth: .infinity, ...)` is *centred* by SwiftUI once the hosting view is smaller than the content, which on the Duo's inner screen shifted the player up and left during the close and left the artwork's bottom edge as a strip at the bar (device recording, 2026-11-12). The VM's outer panel hid this; the inner panel and the phone show it. The artwork reports its frame there through `NowPlayingPresenter.artworkFrame`.

**Close state.** `dismissing`, `wantsShow` and `closeAnimationsStarted`. A present can't start during a close (that crashed UIKit); a tap on the bar during a landing is kept and presented when the close finishes. The transition coordinator's completion settles both outcomes (`closeFinished` or `closeCancelled`); `presentationControllerDidDismiss` is a backup, and `present()` clears a close whose controller is already off screen. A committed drag sets `showNowPlaying = false` at release, not at the end. The bar opens through `NowPlayingPresenter.open()` (sets the flag *and* asks for the presentation), and `presentationControllerDidDismiss` finishes the bookkeeping itself if `willDismiss` never ran: otherwise the player stays marked open and a tap on the bar sets an already-true flag and does nothing (the "doesn't reopen after a flick" report). The presenter used to log every state change (`NP …` lines) and had `-debugCycleNowPlaying <hold> <count>` to loop open and close; that is gone from `main` but kept at the `debug-harness` tag, which is how the flick bug below was found from the phone's own log.

**Flick during the open (fixed 2026-11-13, owner-confirmed on the Duo).** A flick while the card is still opening makes UIKit reverse the presentation itself: no `willDismiss`/`didDismiss`, so none of the close's animations run (black card fill, content offset, card jumps back then closes again), and the presenter was left marked open with nothing on screen (the bar then did nothing). Two defences: `isModalInPresentation = true` from `present()` until the open's transition completes (the sheet's drag can't take hold; an early flick is ignored), and `openFinished` / `healIfStale()` reset a presentation that is no longer attached. The VM never reproduced the reversal (its flicks are ignored or close cleanly); the phone's state log (from the `debug-harness` build, pulled with `devicectl device copy from ... --domain-type appDataContainer --domain-identifier dev.cobre.aioclub --source Library/Logs/signin-log.txt`) showed it as a close with no `willDismiss`.

**Interactive close bookkeeping.** The sheet delegate's `presentationControllerWillDismiss` starts the close, and `notifyWhenInteractionChanges` commits it on release.

**History.**
- First the system zoom, then `.overFullScreen` plus the zoom.
  - `.overFullScreen` made the page behind spring back on close. Switching to a form sheet fixed that.
  - With the zoom, flicks paused for about 0.1 s, then the card shrank into a small box instead of the bar.
- Then a hand-made pan. All replaced as described above in fd82602.

## Layout vs Music: what the vphone VM can and cannot tell you (2026-11-12)

Method (works well): dump Music's UIView frames (`layout.js`: UILabel / UIImageView / sliders / buttons converted to window coordinates) and NeoClub's drawn layers (`layout-neo.js`: leaf CALayers with contents, since SwiftUI draws no views), plus a full-resolution screenshot row scan (bright-pixel runs divided by the panel's height in points) for glyph positions.

**Caveat that cost a wrong turn: vertical positions from Music running in the VM are NOT the phone's.** Music's vertical layout depends on the safe-area insets, which differ between the VM and the phone; NeoClub's is anchored to the screen's edges. The owner's device-screenshot calibrations (the constants in `controls()`, `titleRow` padding, the header's top padding, landscape) are the truth for the phone. Evidence: inner portrait, VM Music minus the phone-calibrated NeoClub was +0.85 pt at the bottom row, +2.8 at the volume, +2.55 at the transport, +3.65 at the scrubber, +6.3 at the title and +11.9 at the artwork top (Up Next header: 41.8 in the VM, 32 on the phone), growing steadily upward like a different top inset. I retuned these to the VM once and then reverted. **Only use the VM for inset-independent things:** sizes and relative gaps inside one piece of UI, motion (card path, springs, timings), which view moves with what, which animations run, centring rules.

Inset-independent facts from Music (kept in the code):
- Up Next, outer screen: header artwork 72 pt; the buttons row (38 pt high) sits 8.2 pt under it; the section header 21 pt under the buttons; queue rows 48 pt artwork on a 56 pt pitch. (NeoClub: speed and sleep capsules instead of Music's shuffle/repeat/infinity/clear; an extra "From ..." line under "Up Next" that Music doesn't have, which puts its first row about 12 pt lower.)
- Landscape with Up Next closed: Music centres the column on the **whole window** (artwork centre x 475.7 of 951); NeoClub's column was centred in the area left after the status-column inset (42 pt left). Fixed with an offset of (trailing inset minus leading inset) / 2 in artwork mode. With Up Next open Music's list is at x 507.7 (width 343.3, 16 pt in from the inset edge), its column title at x 52: this agrees with the owner's device numbers, so horizontal geometry in the VM matches the phone.
- Paused artwork is 330 pt base x 0.73 = 241 pt in landscape (NeoClub's base was height-limited to 317 by the inset-reduced height; not changed, it is vertical).

If vertical positions need checking again, get a device screenshot of Music and NeoClub in the same state and compare in pt (3 px per pt on the Duo).

### Device calibration against Music, 2026-11-13 (the numbers now in the code)

The owner took the same states on the Duo in Music and NeoClub (outer, inner portrait, landscape; playing, Up Next, Info/Lyrics) with the text size set smaller. Method: put each pair side by side with a pixel ruler (`PIL`; no numpy was available), read positions in pt (2.951 px/pt on the outer screen, 2.103 on the inner screen), and find the scrubber and volume tracks by scanning one column for bright runs. Differences found, and what changed:

| State | Was | Now |
|---|---|---|
| Outer, Up Next | header artwork 51 pt from the top; speed/sleep capsules 44 pt tall (`SpeedButton` is 44 pt and `minHeight: 38` didn't cap it) | header 32 pt from the top (as Music, on both screens); capsules a fixed 37 pt; 8.4 pt under the header; panel 13.4 pt under them |
| Outer, playing | transport 3.7 pt high, times 1.8 pt high, bottom row 1.2 pt low | transport padding 1.9, volume padding 22.3, bottom-row padding 20.8, bottom padding 17.2; scrubber-to-times gap 5.8 (everywhere) |
| Inner portrait, playing | artwork 1.7 pt high, scrubber 1.4 pt low, bottom row 1.7 pt low | title padding 32.3, scrubber padding 18.5, bottom-row padding 34.7, bottom padding 17.7 |
| Landscape, playing | artwork 317 pt (capped by the inset-reduced height) instead of 330; whole column 8.6 pt high; title row 2.4 pt high | artwork 330 (cap from the full window height); column shifted down 8.6 pt (`.padding(.bottom, -8.6)`); scrubber padding 9.6 |
| Landscape, Up Next | list 3.8 pt low, then rows 1.9 pt low | panel top padding 14.3 |

After the changes every pair matched within about 1 pt (scrubber and volume tracks within 0.5 pt). Not compared: Info versus Lyrics panels (different content), laptop posture. Rows were compared with a real queue (56 pt pitch, 48 pt artwork on both).

### Fold / unfold between portrait and laptop posture (2026-11-13)

From the owner's side-by-side recording of NeoClub and Music on the inner screen:
- **Unfold.** NeoClub used to swap `portraitLayout` for `laptopLayout`, so the controls cross-faded at two different positions (two sets of transport buttons visible at once). Music slides one set of controls into place while the artwork grows, about a quarter second. Now the scrubber, transport, volume and bottom row carry `matchedGeometryEffect` ids (`scrubber`, `transport`, `volume`, `bottomBar`) in both layouts, next to the existing `artwork`/`titles`/`actions` ids, so they glide; the layout spring is `response 0.3, damping 0.88`.
- **Fold.** The system sweeps a dark, blurred crease over the lower half. Music keeps its layout still under that sweep and shrinks the artwork about 0.5 s after it starts (hidden), so the controls reappear already in place. NeoClub used to relayout the moment the hinge reported, in plain view. `HingeReader` (bottom of `NowPlayingView.swift`) now reports half-folded 500 ms after the *first* `.partiallyOpen` report (the hinge keeps reporting while it moves; restarting the timer on each report made the shrink late) and reports unfolding at once.
- Checked in the VM with `display.posture` `partially-open` / `open` (hinge values: ambiguous, closed, open, open-flat, partially-open) and burst screenshots (`fold.py`-style capture). Confirmed on the phone: pending.

## Open items / next steps

1. **Release.** Run `scripts/make-release.sh` from a clean tree and give the owner the printed values for their AltStore source (they host it). They test the *Release* build once on the Duo first: tap, drag and flick closes, reopen after a flick, a flick right after opening, sign-in surviving a relaunch (and the app opening on Home), playback on Whit's Flop only, lock-screen controls, downloads, all three screen layouts.
2. **Not compared with Music yet:** the Info versus Lyrics panels, laptop posture, flick release-velocity feel, and the first half second of an open (a flick there is ignored; Music's behaviour unchecked).
3. **Left as designed differences:** an extra "From ..." line under "Up Next"; speed and sleep capsules instead of shuffle/repeat; Jacoby/Univers type.

## Debug tools (removed from `main`, kept at tag `debug-harness`)

Everything that was `#if DEBUG` or launch-argument driven is gone from the app so a release has none of it. The last commit that has it is tagged `debug-harness` (`git show debug-harness`). To use it, check that tag out into a separate worktree (`git worktree add ../NeoClub-debug debug-harness`), build from there and never merge it back:
- launch arguments: `-debugUIOnly` (placeholder episode, no account), `-debugPlayTest` (plays Whit's Flop with its album queued), `-debugTab browse|library|search`, `-debugAlbum`, `-debugEpisode <id>`, `-debugRestoreTestEpisode` (Whit's Flop back to Complete at 1301240), `-debugDownload <id>`, `-debugCycleNowPlaying <hold> <count>`
- `NowPlayingPresenter.trace` (state machine log to `Library/Logs/signin-log.txt`), `SignInLog`, `DebugAPILog` (raw responses in `Library/Logs/api-log`)
- the Debug menu (hold the profile picture on Home) and API Explorer
- `-DFORCE_UI_ONLY` for VM builds with no account (`-DFORCE_NO_SYNC` stays in `main`)

## Tooling and recipes

**Devices.**
- **Duo (physical):** UDID `00008160-000A086C36C0000A`. If the install fails with CoreDeviceError 4016, the phone is locked; ask the owner to unlock it.
  ```
  xcodebuild -project NeoClub.xcodeproj -scheme NeoClub -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/device -allowProvisioningUpdates build
  xcrun devicectl device install app --device 00008160-000A086C36C0000A build/device/Build/Products/Debug-iphoneos/NeoClub.app
  ```
- **Simulator** (iPhone Duo `08AAC54F-5DE5-40F1-B0C4-923E07C66A7C`):
  - display 1 is the outer screen, 1398×2034 px; there's no fold control
  - the first launch shows white for about 6–9 s
  - taps get dropped sometimes, so take a screenshot before retrying
  - a placeholder episode with no account needs the `debug-harness` build (`-debugUIOnly`)
  - record with `xcrun simctl io <S> recordVideo --display=1 --force out.mov`; the recordings are smooth and good for timing
  - set Dynamic Type with `xcrun simctl ui <S> content_size <size>`
  - local Frida can't attach to simulator apps
- **vphone VM `duo-lab`** (`vphone-launchpad-cli guest rpc duo-lab <method> '<json>'`):
  - commands:
    - `apps.launch {"bundle_id":…}`
    - `input.tap {x,y}`
    - `input.swipe {x1,y1,x2,y2,duration}`
    - `screen.screenshot {max_dimension}` (base64 JPEG)
    - `display.posture {"hinge":"closed","orientation":"portrait"}` for the outer screen; `{"hinge":"open","orientation":"landscape-left"}` for inner portrait
  - Install by zipping `Payload/NeoClub.app` into an IPA, then `guest push duo-lab <ipa> /private/var/tmp/`, then `apps.install {"path":…}`.
  - The VM is signed in to the real account, so VM builds need `OTHER_SWIFT_FLAGS='$(inherited) -DFORCE_NO_SYNC'` (`-DFORCE_UI_ONLY` exists only in the `debug-harness` tag), built to `build/vm`.
  - Apple Music in the VM has a song queued and is the reference for tracing.
- **Frida against the VM:**
  - `frida -H 192.168.64.7 -n <Music|NeoClub> -q -t <secs> -l script.js < /dev/null`
  - Attach by process name; `frida-ps` fails without a TTY.
  - If it says "unable to connect", restart the server: `vphone-launchpad-cli guest rpc duo-lab services.load '{"paths":["/private/var/frida/re.frida.server.plist"]}'`.
  - **Sampling geometry:** poll on a 10 ms timer, schedule onto the main queue once at a time (a flood of scheduled blocks hung Music's main thread and needed an app restart), find the *last* `UIDropShadowView` (there are two), and log each descendant's presentation-layer frame converted to window coordinates (`pl.convertRect_toLayer_(pl.bounds(), NULL)`). Normalise by the card's frame to see what is pinned, scaled or clipped.
  - **Inner screen in the VM:** `display.posture '{"hinge":"open","orientation":"landscape-left"}'` gives the 669x951 pt inner panel in portrait (input coordinates stay in the 466x678 space, scaled; the bar is at about (233, 593)). Use it for anything the phone shows on the inner screen. `display.posture` can answer "machine refused" once; retry.
  - **Guest agent drops:** after a build/install or heavy Frida use, vphone's guest agent can disconnect for a minute ("The guest agent is not connected"); poll `device.network` until it answers, then continue.
  - **macOS Local Network permission:** Frida reaches the VM over the host network (192.168.64.x). If the app hosting the session lacks Local Network permission, everything fails with "No route to host" while vphone's own channel (rpc, screenshots, input) still works. The owner has to enable it (System Settings, Privacy & Security, Local Network).
  - The Python venv with frida and numpy lived in the old session's scratchpad; recreate it with `python3 -m venv … && pip install frida-tools numpy`.
  - Useful hooks:
    - `-[CALayer addAnimation:forKey:]`: log the view class, key path, spring mass/stiffness/damping/velocity, from/to values and frame
    - `UIViewPropertyAnimator` `startAnimation` with `timingParameters`
    - `-[_UISheetAnimationController set*:]`
    - `animationControllerForDismissedController:` on Music's `PalettePresentationInteraction`
  - Don't call every getter on UIKit objects; it crashed NeoClub. Call only the ones you need.

**Measuring the owner's recordings.**
- 1398×2034 px is the outer screen (÷3 = 466×678 pt); about 2008×2854 px is the inner screen (about 669×951 pt).
- Recordings are variable frame rate; read real timestamps with `ffprobe -show_entries frame=pts_time`.
- Make contact sheets with `ffmpeg -vf "fps=…,scale=…,tile=…"`.
- To track motion, build a time-strip: crop a narrow column (for example `crop=12:278:640:0`) and tile it across time.
- This Homebrew ffmpeg has no `drawtext` filter.
