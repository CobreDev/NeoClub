# NeoClub handoff

Last updated 2026-11-12. HEAD is `fd82602` on `main`.

## Goal

NeoClub is a native SwiftUI replacement for the official **Adventures in Odyssey Club** app, which is built in Flutter and is clunky. It's for the owner's own use on an **iPhone Duo** (foldable). It's installed directly from Xcode and through the owner's private AltStore source.

The bar for every screen is **"behaves exactly like Apple Music"** (iOS 27): layout, gestures, springs, sheet presentation and Liquid Glass. The visual identity stays AIO Club: Jacoby and Univers fonts, AIO blue, honeycomb backgrounds, official art and the official icon. Users see the name "AIO Club"; "NeoClub" is only the project name.

When matching Music, the method that works is to **measure Music, not guess**:
- trace the real Music app with Frida in the vphone VM
- step through the owner's screen recordings frame by frame

Copy the mechanism Music actually uses (often a private UIKit setting) rather than imitating the look by hand.

## Current state

- Version **1.0 (build 1)**, bundle ID `dev.cobre.aioclub`, team `4BN7V65X8J`, iOS 26.2+, XcodeGen (`project.yml`).
- v1 scope is done:
  - sign-in (OAuth, the official client ID), profiles with PINs
  - Home, Browse, Library, Search, episode and album pages
  - player with background audio, lock screen, Up Next (Play Next and Play Last), progress sync
  - downloads (background session), bookmarks
  - Dynamic Type
  - outer and inner Duo layouts, including laptop posture and split view
- 13 unit tests in `NeoClubTests` pass.
- **The latest debug build (fd82602) is on the owner's Duo.** The owner hasn't confirmed the new Now Playing close on the phone yet. That's the open question.
- `dist/NeoClub-1.0.ipa` was built *before* fd82602. Rebuild it with `scripts/make-release.sh` before publishing.

## Hard rules (owner's instructions)

1. **Account safety.** The real paid AIO account is used. Mirror the official client's requests: headers `X-Experience-Name`, `X-VIEWER-ID`, `X-PIN` and the same OAuth parameters. Keep API probing to a few spaced-out read-only GETs. **Ask before any write**: progress, ratings, profile or PIN, membership. Never type the owner's password or PIN; they sign in themselves.
2. **Progress safety.** Sync is ON in normal builds.
   - Test playback only on **#001 Whit's Flop** (`a354W0000046TjUQAU`, Cooper profile).
   - Restore it with the `-debugRestoreTestEpisode` launch argument: Complete at 1301240.
   - Never play, seek or mark played any other episode without asking.
   - Simulator testing without writes: `-syncProgress NO`, or the `-debugUIOnly` placeholder mode.
   - VM builds signed in to the real account must use `-DFORCE_NO_SYNC`.
   - Ignore the episodes that were finished locally while sync was off. Never push them.
3. **Native components.** Use system bars, blurs, menus, sheets and glass. No hand-drawn imitations.
4. **Duo inner screen.** Full-width single-page browsing. No list/detail two-pane split.
5. **vphone.** Use it as designed. Don't edit the VM's `config.plist` screen config. Change the fold with `display.posture`. Don't change host security settings, SIP or boot-args.
6. Commit only when asked or when finishing agreed work. Don't push. `dist/` is gitignored.

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
| Debug menu | hold the profile picture on Home → `Features/Debug/DebugMenu.swift` (sync toggle, Files export, API Explorer) |
| Research notes | `docs/original-app-analysis.md` (API notes, Music traces) |
| Release | `scripts/make-release.sh` builds a Release IPA into `dist/` and prints the version, build, date, size and minimum OS for the owner's existing AltStore source. **Don't generate a source.json**: the owner already has a source. |

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

**Close state.** `dismissing`, `wantsShow` and `closeAnimationsStarted`. A present can't start during a close (that crashed UIKit); a tap on the bar during a landing is kept and presented when the close finishes. The transition coordinator's completion settles both outcomes (`closeFinished` or `closeCancelled`); `presentationControllerDidDismiss` is a backup, and `present()` clears a close whose controller is already off screen. A committed drag sets `showNowPlaying = false` at release, not at the end. The bar opens through `NowPlayingPresenter.open()` (sets the flag *and* asks for the presentation), and `presentationControllerDidDismiss` finishes the bookkeeping itself if `willDismiss` never ran: otherwise the player stays marked open and a tap on the bar sets an already-true flag and does nothing (the "doesn't reopen after a flick" report). DEBUG builds log every state change to `Library/Logs/signin-log.txt` (lines starting `NP`); `-debugCycleNowPlaying <hold> <count>` opens and closes it in a loop.

**Interactive close bookkeeping.** The sheet delegate's `presentationControllerWillDismiss` starts the close, and `notifyWhenInteractionChanges` commits it on release.

**History.**
- First the system zoom, then `.overFullScreen` plus the zoom.
  - `.overFullScreen` made the page behind spring back on close. Switching to a form sheet fixed that.
  - With the zoom, flicks paused for about 0.1 s, then the card shrank into a small box instead of the bar.
- Then a hand-made pan. All replaced as described above in fd82602.

## Open items / next steps

1. **The owner checks the new close on the Duo.** Flick, slow drag, tap the grabber, laptop posture, and a list scrolled down in Up Next. They also check that dragging still feels right: it now uses the sheet's own resistance and its rules for closing versus snapping back. If something's off, ask for a screen recording of NeoClub and Music doing the same gesture.
2. **Not yet checked:**
   - **Not checked at all:** the close on the Duo's inner screen, portrait and landscape (bar-slot geometry, the wide bar layout), and in split view.
   - **Checked only in the simulator placeholder build:** the close with Up Next or Info open (the small header artwork).
3. **Release:** once the owner is happy, run `scripts/make-release.sh` and give them the printed values for their AltStore source entry.
4. Smaller follow-ups:
   - Compare the open animation with Music again now that the presentation has changed.
   
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
  - launch with `-debugUIOnly` for a placeholder episode with no account
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
  - The VM is signed in to the real account, so VM builds need `OTHER_SWIFT_FLAGS='$(inherited) -DFORCE_NO_SYNC'` (or `-DFORCE_UI_ONLY` for no account), built to `build/vm`.
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
