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

**Open.** Our own `OpenAnimator`, through `transitioningDelegate`:
- the card grows out of the bar on Music's spring (mass 1, stiffness 333.33, damping 36.51)
- it starts as glass that fades off the player
- flat 12% black dim behind; nothing behind moves

**Close.** `animationController(forDismissed:)` returns UIKit's private `_UISheetAnimationController` with `isReversed = YES` and `sourceFrame` = the bar's frame in the window. This is exactly what Music's `PalettePresentationAnimationController` subclass sets. UIKit does the rest:
- On release, the card shrinks to the bar's size where it is, then springs into the bar, keeping the flick's velocity.
- The bar's glass follows the card through `CAMatchPropertyAnimation`s.

Without `sourceFrame`, the card slides off the bottom of the screen.

**Drag.** The sheet's own pan (`_UISheetInteraction`), as in Music. The old hand-made `PresentedCard` pan is gone. Don't reapply detents while a drag is in progress: it made the sheet spring back instead of closing.

**Close stand-ins** (`runCloseAnimations`). SwiftUI can't follow the card's frame animation. Music lays its player out again at bar size; we imitate that with UIKit stand-ins:
- Snapshot the player above and below the artwork. Autoresizing pins the top part to the card's top and the bottom part to the card's bottom, so the controls ride up with the card's bottom edge.
- Fade them on Music's curve: 0.7153 s, cubic (0.1878, 0.0023, 0.5399, 0.9629), sampled from its overdamped spring (mass 3, stiffness 500, damping 1000).
- A copy of the artwork flies on the 333.33/36.51 spring to the bar's artwork slot: 32 pt, 14 pt from the leading edge, corner radius 6.
- The bar's content fades in over 0.5 s.
- The real artwork and its shadow hide through `NowPlayingPresenter.isClosing`.
- For a tap close, `runCloseAnimations` runs *before* `dismiss` so the stand-ins resize with the card.

**Fixed layout.** `NowPlayingPresentation` lays the player out at the window's size, pinned top-leading, in the named coordinate space `nowPlaying`. The artwork reports its frame there through `NowPlayingPresenter.artworkFrame`.

**Reopen gate.** `dismissing` and `wantsShow` stop a present from starting during a close. Doing that crashed UIKit.

**Interactive close bookkeeping.** The sheet delegate's `presentationControllerWillDismiss` starts the close, and `notifyWhenInteractionChanges` runs the stand-ins on release. `presentationControllerDidDismiss` sets `showNowPlaying = false`.

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
   - Music's grabber fades on its own keyframes; ours fades with the top stand-in.

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
