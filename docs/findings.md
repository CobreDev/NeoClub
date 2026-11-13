# Findings and pitfalls

Non-obvious things learned building NeoClub, grouped by area. The long write-ups live in [now-playing.md](now-playing.md) and [layout-vs-music.md](layout-vs-music.md); this is the checklist of what bit us.

## Method

- **Measure Music, don't guess.** Three sources, in order of authority for the phone: (1) the owner's same-state device screenshots of Music and NeoClub, compared side by side with a pixel ruler in points (2.951 px/pt on the outer screen, 2.103 on the inner screen); (2) the owner's screen recordings, stepped frame by frame; (3) Frida traces of Music in the vphone VM for *mechanisms* (which class animates, springs, timings, what moves with what).
- **The VM can't settle vertical positions.** Its safe-area insets differ from the phone's, so Music's vertical layout there is not the phone's. A retune to the VM was made once and reverted. Use the VM for motion, sizes, relative gaps and centring rules only.
- **Copy the mechanism, not the look.** Music's close is UIKit's own `_UISheetAnimationController`, configured the way Music's `PalettePresentationAnimationController` configures it. Hand-built imitations (a custom pan, snapshot stand-ins, a hand-made card) were all wrong in ways only side-by-side recordings showed.
- **A debug log read off the phone beats guessing.** The "flick during open" lockup was found by pulling the Debug build's state log with `devicectl device copy from ... Library/Logs/signin-log.txt` and seeing a close with no `willDismiss` (see [now-playing.md](now-playing.md)). The tooling that wrote it is at the `debug-harness` tag.

## UIKit and Now Playing

- Music's sheet needs private settings (`_wantsFullScreen`, `_allowsInteractiveDismissWhenFullScreen`, `_cornerRadiusForPresentationAndDismissal`) and its source set through the private `_setSourceView:` as well as the public property. Without `_allowsInteractiveDismissWhenFullScreen` the sheet's drag recognizer stays disabled.
- Without `sourceFrame` on the animator, the card slides off the bottom of the screen instead of landing in the bar. `isReversed = YES` for the close.
- Don't reapply detents mid-drag: the sheet springs back instead of closing.
- Music's content is never scaled or moved in the card while it shrinks: it is pinned top-left and clipped. Anything that rides up with the bottom edge is wrong.
- Fading the tab accessory view fades its Liquid Glass in from nothing (a black pill). Fade only the SwiftUI content. The card's own `UIDropShadowView` background is opaque black in dark appearance and must be animated to clear on the card's spring.
- `UIImageView(image:)` starts at the image's natural size: created inside a transition's animation context it animates in from that size. Use `UIImageView(frame:)` and add it inside `performWithoutAnimation`.
- SwiftUI centres a fixed-size frame inside a flexible `.frame(maxWidth: .infinity)` once the host is smaller than the content. Pin with an `overlay(alignment: .topLeading)` on a `Color.clear` base.
- Delegate callbacks are not guaranteed: `willDismiss` can be skipped (heal in `didDismiss`), a present during a close crashes UIKit (defer it to the close's completion), and a flick *during the open* makes UIKit reverse the presentation with no dismissal callback at all (disable the sheet's drag until the open completes, and heal stale state).
- Via Frida: don't flood the main queue (poll with one pending tick), find the *last* `UIDropShadowView` (there are two), and don't call every getter on UIKit objects (it crashed NeoClub).

## Fold and unfold (portrait to laptop posture)

- Swapping two layouts in an `if/else` cross-fades their views, so controls at different positions showed up twice. Give the controls `matchedGeometryEffect` ids in both layouts so one set glides.
- The hinge reports the fold at its start and keeps reporting as it moves. Music relayouts under the system's dark sweep about 0.5 s later. Start a 0.5 s timer on the first `.partiallyOpen` report only (restarting on each report made the shrink late), and report unfolding at once.

## SwiftUI and UI details

- A `Menu`'s glass morph follows its label's bounds. `SpeedButton` and `SleepTimerButton` had 44 pt square labels inside wide Up Next capsules, so the menu opened from and closed into a circle, and `minHeight: 38` on the capsule never took effect (the capsule was really 44 pt). The capsule must be the label.
- Text dimmed to 60% at its default value (`1×`, the moon) reads as disabled inside a capsule.
- The player's controls are laid out from the bottom up as a chain of paddings. To move one element without moving its neighbours, change the paddings on both sides of it in opposite directions (this is how the 1 to 2 pt calibrations were applied).
- Restoring navigation across launches (`@SceneStorage`) rebuilt an album page from a bare ID with no preview, which showed a black rectangle where its header should be. Place is now remembered per process only (`SceneMemory`), which still survives the window being recreated when the Duo is unfolded, and a fresh launch opens Home.
- The podcast logo is itself a bright green, so a minty Podcasts tile blended into it. Podcasts is a deep forest green and Series is blue.
- API image URLs contain spaces and apostrophes (`content grouping/connie's_conversion…`). `URL(string:)` percent-encodes them on iOS 17+, they download fine, and the CDN serves them as `binary/octet-stream`, which ImageIO decodes anyway.

## App icon

- Icon Composer `.icon` documents can be written by hand (`icon.json` plus `Assets/*.png`; layers are `glass: true/false`, groups are front to back) and rendered without the app by Icon Composer's `ictool`, which also shows exactly how iOS 27 will draw them. `/usr/bin/ictool` is an `xcrun` shim for `actool`'s icon compiler and doesn't have `--export-image`; use the binary inside `Icon Composer.app/Contents/Executables`.
- (Not in use: alternate icons.) They work with `.icon` files: list their names in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` and the built `Info.plist` gets `CFBundleAlternateIcons`; the app can't preview an icon by name, so a picker needs rendered thumbnails. The `icon-glass` branch has such a picker if one is ever wanted again.
- Dark, Clear and Tinted looks: a dark-on-gold icon becomes dark-on-dark (illegible) when iOS darkens or tints it. Hand-written `image-name-specializations` and top-level `fill-specializations` are silently ignored by Icon Composer, but `hidden-specializations` (per layer, appearances `dark` and `tinted`; Clear uses the tinted look) works, so `make_gold` in `icons/build_icons.py` has three sets of layers and hides the others per appearance: gold with the original colours (light), the system's own dark material with a gold wordmark (Dark: no background layer, and the icon's own `fill` is `automatic`, with no colour at all: a gold `fill` overridden for Dark with `fill-specializations` rendered neutral in `ictool` but made iOS tint the whole Dark icon yellow on the phone, so gold lives only on the Light look's background layer; a hand-picked gray never matched the other apps' dark icons), transparent honeycomb lines and a white wordmark over no background image (Tinted/Clear, where the system supplies the tile and colours it). Check every look with `ictool --rendition Default|Dark|ClearLight|ClearDark|TintedLight|TintedDark` (see docs/images/app-icon-gold-appearances.png).
- An opaque image in the Tinted/Clear background (the earlier hand-picked dark gray honeycomb) blocks the system's glass: the tile stayed a flat gray square with no wallpaper showing through next to every other app's translucent tile. Keep that look's background to transparent lines (`honeycomb_layer`), and check it by switching the simulator's Home Screen to Clear and Tinted (long-press the home screen, Edit, Customize); `icontool --export-preview` only knows Default, Dark and Mono and crashes in `FilePath.swift` on this machine.
- The wordmark's 'Club' and arc are separate connected components in the alpha channel, which is how the two-colour variants split it into layers.

## Unexplained

- The Series and Podcasts category tiles were blank for one launch while Collections and Books showed covers. The images were reachable, cached on the phone, and the cached responses decoded fine with the app's own models, so data, URLs and decoding were ruled out. They appeared on a later launch. If it recurs, look at `BrowseStore.load()` (it loads once per process behind a `loaded` flag and its work is cancelled when the view's task is cancelled) and at what the first launch after an install can fetch.

## Process and build

- Release builds get the build number and commit through `CURRENT_PROJECT_VERSION` / `NEOCLUB_COMMIT` build settings; `xcodegen generate` rewrites the tracked `NeoClub/Info.plist`, so generate before checking the tree is clean.
- `xcodebuild ... -quiet` sometimes prints `error: the following command failed with exit code 0 but produced no further output` and still succeeds; check for `BUILD SUCCEEDED` without `-quiet`.
- Verify a release by unzipping the IPA: check `CFBundleVersion`, `NeoClubCommit` in its `Info.plist`, and `strings` the binary for leftover debug strings.
- Shell: in zsh, an unquoted `--include=*.swift` is globbed (quote it); macOS `sed -i` needs an empty suffix argument.
- **Episodes of an album that isn't fully out have no `album_name`.** Detail and list responses leave it empty for the newest album (seen with #1046 in "#83: Phase One"), so Now Playing, the lock screen and CarPlay fell back to "Adventures in Odyssey". `AIOService.episode` now fills it in from `AlbumIndex` (episode id to album name, built from the Album pages that Next Up and the Albums grid already request, saved pages first), then from a sibling in `in_album`, then from the grouping the episode was opened from.
- **Album pages carry no air dates.** `contentgroupings` responses give each episode no `air_date` (only the album's `album_copyright_year`); an episode's detail does, for itself and for every sibling in `in_album` (some siblings have none). The album page's "Released ..." line therefore reads the first playable episode's detail once (`GroupingView.loadAirDates`), and falls back to the copyright year.
