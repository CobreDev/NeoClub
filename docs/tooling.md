# Tooling and recipes

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

## Debug tools (removed from `main`, kept at tag `debug-harness`)

Everything that was `#if DEBUG` or launch-argument driven is gone from the app so a release has none of it. The last commit that has it is tagged `debug-harness` (`git show debug-harness`). To use it, check that tag out into a separate worktree (`git worktree add ../NeoClub-debug debug-harness`), build from there and never merge it back:
- launch arguments: `-debugUIOnly` (placeholder episode, no account), `-debugPlayTest` (plays Whit's Flop with its album queued), `-debugTab browse|library|search`, `-debugAlbum`, `-debugEpisode <id>`, `-debugRestoreTestEpisode` (Whit's Flop back to Complete at 1301240), `-debugDownload <id>`, `-debugCycleNowPlaying <hold> <count>`
- `NowPlayingPresenter.trace` (state machine log to `Library/Logs/signin-log.txt`), `SignInLog`, `DebugAPILog` (raw responses in `Library/Logs/api-log`)
- the Debug menu (hold the profile picture on Home) and API Explorer
- `-DFORCE_UI_ONLY` for VM builds with no account (`-DFORCE_NO_SYNC` stays in `main`)

## Screenshot demo mode (kept on `main`, compiled only with `-DSCREENSHOT_DEMO`)

For the AltStore listing screenshots, on the iPhone 18 Pro simulator, from a signed-in account without showing anything personal. `scripts/screenshots.sh` builds with the flag, sets the status bar to 9:41 (full battery and signal), launches the app once per screen with `-demoScreen <name>` and saves `screenshots/1-home.png` to `5-now-playing.png` (1206x2622). The code is `NeoClub/App/DemoMode.swift` plus small `#if SCREENSHOT_DEMO` blocks (HomeView, MainTabView's `runDemo`, NowPlayingView's initial mode, AudioPlayer, ProgressSync, MarqueeText); a normal build or release compiles none of it.

- **Sign in once yourself.** Open the simulator in DeviceHub (Xcode 27 has no Simulator.app), tap Sign In and pick the profile. I never type the password or PIN. The sign-in persists in the simulator. `SIM_UDID` overrides the simulator (default: the iPhone 18 Pro, iOS 27.2).
- **No progress anywhere.** `AudioPlayer.progress(for:)` returns nil (no "min left" bars, no played checkmarks), `ProgressSync.isEnabled` is always false (nothing is written to the account), and Home is `DemoHome`: New Albums and Latest Episodes only (no promo carousel, Continue Listening, Next Up, bookmarks, or "Check out more content about ..." recommendations, which come from listening history).
- **Whit's Flop.** The player loads #001 Whit's Flop (`a354W0000046TjUQAU`) with the rest of its album queued, paused at 0:42. The album is found by reading the album list (read-only).
- **Screens:** `home`, `browse`, `album`, `episode`, `nowplaying`, `upnext`, `info`. The listing uses home, browse, album, episode, nowplaying (in that order).
- Long titles are shown at rest (`MarqueeText` doesn't scroll in the demo) so a screenshot is never caught mid-scroll.
- The simulator has no Simulator.app here: `xcrun simctl` (boot, install, launch, `io screenshot`, `status_bar`) does everything.

The AltStore `screenshots` URLs are `https://raw.githubusercontent.com/CobreDev/NeoClub/main/screenshots/<file>` (the repo is public).

## iPhone 18 Pro VM (`iphone18pro`)

A vphone machine made as a regular iPhone for checking layouts at a normal phone size (402 x 874 pt), created 2026-11-13: `vphone-launchpad-cli vm create iphone18pro --device iPhone19,2 --iphone-source <24B119 restore ipsw> --cloudos-source ~/.vphone/ipsws/c0ecdb4b*.ipsw` plus the five `--allow kernel-exp-frida_*` patches `duo-lab` has (13.7 GB download, about 32 GB template, 8 CPUs, 8 GB). Notes:
- The first boot of a new machine needs vphone-vm allowed past AMFI (`sudo .../vphone-escalator allow .../vphone-vm`, which the owner ran); without it creation stops at "AMFI blocked vphone-vm". A failed attempt leaves a template folder in `~/.vphone/machines` to delete by hand (there is no `vm delete`).
- Input coordinates are plain points (402 x 874), unlike the Duo's scaled 466 x 678 space. Screenshots come back 414 x 900 at `max_dimension` 900.
- **Frida is not installed by default.** Push `frida-server` (arm64e, from the Frida `.deb`) and `frida-agent.dylib` into `/private/var/frida/usr/...`, push a launch-daemon plist whose `ProgramArguments` are `[.../frida-server, -l, 0.0.0.0]` (without `-l` it listens on the guest's loopback only), `services.load` the plist (`services.unload` takes the plist `paths`, not a label), then `frida -H <guest ip> -n Music`. The guest IP is in `device.network`.
- Music has no library by default: copy songs in (the owner added some), then play one and open Now Playing.
- Auto-Lock: set to Never in the guest's Settings (Display & Brightness), because a locked guest suspends the app and Frida can't attach. `display.auto_lock` may keep reporting the old value.
- NeoClub there: build with `-DFORCE_NO_SYNC -DSCREENSHOT_UI_ONLY` (no account: placeholder Whit's Flop plus queued placeholder episodes), install with the installer script with `VM=iphone18pro`.
- The same VM can't be switched to a fold posture (`display.posture` says "no device pose override").
