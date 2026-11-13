#!/bin/zsh
# Builds a Release IPA into dist/ for your existing AltStore source.
#
#   scripts/make-release.sh               a new build number
#   scripts/make-release.sh --same-build  rebuild today's latest build number (e.g. after a fix, when the number
#                                          shouldn't change): the tag moves to the new commit, and the old one is kept
#                                          as build-<number>-was-<old hash>
#
# The build number is the date, YYMMDD (261113 for 13 Nov 2026), with .2, .3 … for further builds the same day, so it
# always increases and reads as a date. Each release is tagged `build-<number>` on the commit it was built from
# (`git show build-261113`), and the commit's short hash is stored in the app and shown in Account, so a build on a
# phone can always be traced to its source. The working tree must be clean for that to be true. Tags stay local.
#
# Prints the values to add to the app's `versions` list in your source. AltStore re-signs the app with your own
# Apple ID when it installs it, so the IPA's signature doesn't matter.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate -q
if [[ -n "$(git status --porcelain)" ]]; then
    echo "The working tree has uncommitted changes. Commit them first: the release is tagged with its commit." >&2
    git status --short >&2
    exit 1
fi

COMMIT=$(git rev-parse --short=7 HEAD)
DAY=$(date +%y%m%d)
SAME_DAY=$(git tag -l "build-$DAY" "build-$DAY.[0-9]*" | wc -l | tr -d ' ')
if [[ "${1:-}" == "--same-build" ]]; then
    if [[ $SAME_DAY -eq 0 ]]; then echo "No build has been made today yet." >&2; exit 1; fi
    if [[ $SAME_DAY -eq 1 ]]; then BUILD=$DAY; else BUILD="$DAY.$SAME_DAY"; fi
    OLD=$(git rev-parse --short=7 "build-$BUILD^{commit}")
    if [[ "$OLD" == "$COMMIT" ]]; then echo "build-$BUILD is already this commit." >&2; exit 1; fi
elif [[ $SAME_DAY -eq 0 ]]; then BUILD=$DAY; else BUILD="$DAY.$((SAME_DAY + 1))"; fi

xcodebuild -project NeoClub.xcodeproj -scheme NeoClub -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build/release -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD" NEOCLUB_COMMIT="$COMMIT" build -quiet

APP=build/release/Build/Products/Release-iphoneos/NeoClub.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILT=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
MIN_OS=$(plutil -extract MinimumOSVersion raw "$APP/Info.plist")
if [[ "$BUILT" != "$BUILD" ]]; then echo "The built app says build $BUILT, not $BUILD." >&2; exit 1; fi

DIST=dist
STAGE=build/ipa
rm -rf "${STAGE:?}"
mkdir -p "$STAGE/Payload" "$DIST"
ditto "$APP" "$STAGE/Payload/NeoClub.app"
IPA="NeoClub-$VERSION-$BUILD.ipa"
rm -f "$DIST/$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "../../$DIST/$IPA" Payload)

if [[ -n "${OLD:-}" ]]; then git tag "build-$BUILD-was-$OLD" "build-$BUILD^{commit}"; git tag -f "build-$BUILD" HEAD >/dev/null
else git tag "build-$BUILD" HEAD; fi

SIZE=$(stat -f %z "$DIST/$IPA")
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Built $DIST/$IPA  (tagged build-$BUILD at $COMMIT)"
echo
echo "For your AltStore source (bundle ID $BUNDLE_ID):"
echo "  version:       $VERSION"
echo "  buildVersion:  $BUILD"
echo "  date:          $DATE"
echo "  size:          $SIZE"
echo "  minOSVersion:  $MIN_OS"
