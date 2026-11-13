# NeoClub

A native SwiftUI replacement for the official **Adventures in Odyssey Club** app. For the owner's own use on an iPhone Duo (iOS 26.2+); users see the name "AIO Club". Private repo: https://github.com/CobreDev/NeoClub.

## Goal

NeoClub is a native SwiftUI replacement for the official **Adventures in Odyssey Club** app, which is built in Flutter and is clunky. It's for the owner's own use on an **iPhone Duo** (foldable). It's installed directly from Xcode and through the owner's private AltStore source.

The bar for every screen is **"behaves exactly like Apple Music"** (iOS 27): layout, gestures, springs, sheet presentation and Liquid Glass. The visual identity stays AIO Club: Jacoby and Univers fonts, AIO blue, honeycomb backgrounds, official art and the official icon. Users see the name "AIO Club"; "NeoClub" is only the project name.

When matching Music, the method that works is to **measure Music, not guess**:
- trace the real Music app with Frida in the vphone VM
- step through the owner's screen recordings frame by frame

Copy the mechanism Music actually uses (often a private UIKit setting) rather than imitating the look by hand.

## Status

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
- **Now Playing animations are signed off by the owner** (open, tap close, drag close, flick close, reopen), and the layout was matched to the owner's device screenshots of Music on 2026-11-13 (see [docs/layout-vs-music.md](docs/layout-vs-music.md)).
- **Release prep (2026-11-13):** all debug code is removed from the app (launch arguments, the NP state log, the API log, the sign-in log, the placeholder UI-only mode, the Debug menu and API Explorer, the 10-second sleep timer). The two switches the Debug menu held that are real settings, *Sync Listening Progress* and *Show Downloads in Files*, are now in Account.
- **Launch behaviour:** the app opens on Home after a fresh launch. The tab and pages are remembered only for the life of the process (`SceneMemory` in `MainTabView`), so unfolding the Duo (which recreates the window) keeps your place, but quitting and relaunching does not. (It used to restore the last pages from `@SceneStorage`, rebuilding an album from a bare ID, which showed a black rectangle where its header should be.) The mini player still brings back the last episode, paused.

## Working rules (the owner's instructions)

1. **Account safety.** The real paid AIO account is used. Mirror the official client's requests: headers `X-Experience-Name`, `X-VIEWER-ID`, `X-PIN` and the same OAuth parameters. Keep API probing to a few spaced-out read-only GETs. **Ask before any write**: progress, ratings, profile or PIN, membership. Never type the owner's password or PIN; they sign in themselves.
2. **Progress safety.** Sync is ON in normal builds (switch in Account).
   - Test playback only on **#001 Whit's Flop** (`a354W0000046TjUQAU`, Cooper profile). Use the Cooper profile for everything.
   - Never play, seek or mark played any other episode, and never overwrite episodes that are in progress or the owner's place in an album, without asking. (Once the app is built, moving progress backwards is fine, but not by testing on real progress.)
   - Restoring Whit's Flop to Complete at 1301240 used `-debugRestoreTestEpisode`, which is no longer in the app; build the `debug-harness` tag for it (see [docs/tooling.md](docs/tooling.md)).
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

## Build, run, test

```
xcodegen generate
xcodebuild -project NeoClub.xcodeproj -scheme NeoClub -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/device -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008160-000A086C36C0000A build/device/Build/Products/Debug-iphoneos/NeoClub.app
xcodebuild test -project NeoClub.xcodeproj -scheme NeoClub -destination 'id=08AAC54F-5DE5-40F1-B0C4-923E07C66A7C'   # 13 Swift Testing tests
```

Releases: `scripts/make-release.sh` (see [docs/release.md](docs/release.md)). Devices, the simulator, the vphone VM and Frida: [docs/tooling.md](docs/tooling.md).

## Documentation

| Doc | What's in it |
|---|---|
| [docs/now-playing.md](docs/now-playing.md) | How Now Playing opens and closes (traced from Music with Frida), the state machine, the flick-during-open bug, fold/unfold between portrait and laptop |
| [docs/layout-vs-music.md](docs/layout-vs-music.md) | What the VM can and can't tell you about layout, the device calibration against Music, the constants now in the code |
| [docs/findings.md](docs/findings.md) | Non-obvious findings and pitfalls from the whole project (UIKit, SwiftUI, data, process), and what is still unexplained |
| [docs/release.md](docs/release.md) | Date build numbers, tags, `make-release.sh`, the release checklist, the AltStore values |
| [docs/tooling.md](docs/tooling.md) | Devices, simulator, vphone VM, Frida recipes, measuring recordings and screenshots, the removed debug tools, and the screenshot demo mode (`scripts/screenshots.sh`) |
| [docs/original-app-analysis.md](docs/original-app-analysis.md) | The original app's API and structure, and Music's Now Playing presentation trace |

## Open items

1. **Released:** 1.0 (build 261113) was built on 2026-11-13 and handed to the owner for their AltStore source ([docs/release.md](docs/release.md)). The next release gets a new date build number (`scripts/make-release.sh`).
2. **Not compared with Music yet:** the Info versus Lyrics panels, laptop posture, flick release-velocity feel, and the first half second of an open (a flick there is ignored; Music's behaviour unchecked).
3. **Left as designed differences:** an extra "From ..." line under "Up Next"; speed and sleep capsules instead of shuffle/repeat; Jacoby/Univers type.
