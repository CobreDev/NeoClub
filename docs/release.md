# Releasing

The app is installed through the owner's own AltStore source (never generate a `source.json`: they already have one). AltStore re-signs the app with the owner's Apple ID, so the IPA's own signature doesn't matter.

## Build numbers

The build number (`CFBundleVersion`) is the date, `YYMMDD` (`261113` = 13 Nov 2026), with `.2`, `.3` for further builds the same day. It always increases, reads as a date, and can be looked up later:

- `git show build-261113` shows the commit that build was made from. `scripts/make-release.sh` creates the tag.
- The short commit hash is also baked into the app (`NeoClubCommit` in `Info.plist`, from the `NEOCLUB_COMMIT` build setting) and shown in Account's footer: "AIO Club 1.0 (261113 · 0b90dbf)" (`NeoClub/App/AppVersion.swift`).
- Dev builds from Xcode are build `0`, commit `dev`.
- The marketing version is `MARKETING_VERSION` in `project.yml` (1.0).

## Making a release

```
scripts/make-release.sh               # a new build number
scripts/make-release.sh --same-build  # rebuild today's latest number
```

Both need a clean, committed tree (the tag must be the truth) and write `dist/NeoClub-<version>-<build>.ipa` (`dist/` is gitignored). They print the values for the AltStore source entry: version, buildVersion, date, size, minOSVersion (add the file's `sha256` with `shasum -a 256` if the source wants one).

`--same-build` is for a fix that shouldn't change the number (as on 13 Nov 2026, when the owner asked to keep 261113): the tag `build-261113` moves to the new commit and the old one is kept as `build-261113-was-<old hash>`. AltStore won't see a same-number build as an update, so the owner deletes and reinstalls.

Tags are local until pushed (`git push origin --tags`); push only when asked.

## Before publishing

1. `xcodebuild test` passes (13 tests).
2. Unzip the IPA and check `CFBundleVersion`, `NeoClubCommit`, and that `strings` finds none of the removed debug strings.
3. The owner installs the *Release* build once and runs through, on the Duo: tap, drag and flick closes and a reopen after a flick; a flick right after opening (ignored for the first half second by design); the app opening on Home after a quit and relaunch (and keeping its place when folding/unfolding); fold and unfold in Now Playing; the Up Next speed and sleep menus; sign-in surviving a relaunch; playback on #001 Whit's Flop only; lock-screen controls; downloads; outer screen, inner portrait and landscape.
4. The owner uploads the IPA and updates the source entry.

## Release history

- **1.0 (261113)**, 13 Nov 2026. First release. Built three times the same day under the same number: `9883605` (release prep), `5907574` (fold/unfold, category colours), `0b90dbf` (Up Next capsule menus); the shipped one is `build-261113` = `0b90dbf`.

## Account safety while testing

Progress sync is on in release builds (switch in Account). Only play #001 Whit's Flop (`a354W0000046TjUQAU`, Cooper profile) when testing, and never any other episode without asking. Restoring Whit's Flop to Complete at 1301240 needs the `debug-harness` build (`-debugRestoreTestEpisode`), see [tooling.md](tooling.md).
