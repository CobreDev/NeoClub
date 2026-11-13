# Now Playing: how it works (from tracing Music)

The presentation, open, close and drag of the Now Playing card, and everything learned matching it to Apple Music on iOS 27. Code: `NeoClub/Player/NowPlayingPresenter.swift`, `NowPlayingView.swift`, `MainTabView.swift` (`NowPlayingPresentation`).

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

## Fold / unfold between portrait and laptop posture (2026-11-13)

From the owner's side-by-side recording of NeoClub and Music on the inner screen:
- **Unfold.** NeoClub used to swap `portraitLayout` for `laptopLayout`, so the controls cross-faded at two different positions (two sets of transport buttons visible at once). Music slides one set of controls into place while the artwork grows, about a quarter second. Now the scrubber, transport, volume and bottom row carry `matchedGeometryEffect` ids (`scrubber`, `transport`, `volume`, `bottomBar`) in both layouts, next to the existing `artwork`/`titles`/`actions` ids, so they glide; the layout spring is `response 0.3, damping 0.88`.
- **Fold.** The system sweeps a dark, blurred crease over the lower half. Music keeps its layout still under that sweep and shrinks the artwork about 0.5 s after it starts (hidden), so the controls reappear already in place. NeoClub used to relayout the moment the hinge reported, in plain view. `HingeReader` (bottom of `NowPlayingView.swift`) now reports half-folded 500 ms after the *first* `.partiallyOpen` report (the hinge keeps reporting while it moves; restarting the timer on each report made the shrink late) and reports unfolding at once.
- Checked in the VM with `display.posture` `partially-open` / `open` (hinge values: ambiguous, closed, open, open-flat, partially-open) and burst screenshots (`fold.py`-style capture). Confirmed on the phone: pending.
