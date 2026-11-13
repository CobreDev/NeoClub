#!/bin/zsh
# Builds a Release IPA into dist/ for your existing AltStore source.
#
#   scripts/make-release.sh
#
# Prints the version, build number, size and date to add to the app's `versions` list in your source.
# AltStore re-signs the app with your own Apple ID when it installs it, so the IPA's signature doesn't matter.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate -q
xcodebuild -project NeoClub.xcodeproj -scheme NeoClub -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build/release -allowProvisioningUpdates build -quiet

APP=build/release/Build/Products/Release-iphoneos/NeoClub.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")
MIN_OS=$(plutil -extract MinimumOSVersion raw "$APP/Info.plist")

DIST=dist
STAGE=build/ipa
rm -rf "${STAGE:?}"
mkdir -p "$STAGE/Payload" "$DIST"
ditto "$APP" "$STAGE/Payload/NeoClub.app"
IPA="NeoClub-$VERSION.ipa"
rm -f "$DIST/$IPA"
(cd "$STAGE" && /usr/bin/zip -qry "../../$DIST/$IPA" Payload)

SIZE=$(stat -f %z "$DIST/$IPA")
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Built $DIST/$IPA"
echo
echo "For your AltStore source (bundle ID $BUNDLE_ID):"
echo "  version:       $VERSION"
echo "  buildVersion:  $BUILD"
echo "  date:          $DATE"
echo "  size:          $SIZE"
echo "  minOSVersion:  $MIN_OS"
