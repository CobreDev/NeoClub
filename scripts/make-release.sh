#!/bin/zsh
# Builds a Release IPA and the AltStore source that lists it.
#
#   scripts/make-release.sh <base-url> [notes]
#
# <base-url> is where the files in dist/ will be uploaded (for example https://example.com/neoclub). The IPA, the
# icon and source.json all go there; add <base-url>/source.json to AltStore as the source. AltStore re-signs the
# app with your own Apple ID when it installs it, so the IPA's signature doesn't matter.
set -euo pipefail
cd "${0:A:h}/.."

BASE_URL="${1:?usage: scripts/make-release.sh <base-url> [notes]}"
BASE_URL="${BASE_URL%/}"
NOTES="${2:-}"

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
cp NeoClub/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-any.png "$DIST/icon.png"

SIZE=$(stat -f %z "$DIST/$IPA")
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# AltStore source format 2.0.
python3 - "$DIST/source.json" <<EOF
import json, sys
source = {
    "name": "NeoClub",
    "identifier": "$BUNDLE_ID.source",
    "subtitle": "A native player for the Adventures in Odyssey Club.",
    "iconURL": "$BASE_URL/icon.png",
    "tintColor": "#1E5AA8",
    "apps": [{
        "name": "AIO Club",
        "bundleIdentifier": "$BUNDLE_ID",
        "developerName": "CobreDev",
        "subtitle": "Adventures in Odyssey Club, in the style of Apple Music.",
        "localizedDescription": "A native SwiftUI player for the Adventures in Odyssey Club: Home, Browse, Library and Search, downloads, bookmarks, Up Next, and listening progress synced with your Club account.",
        "iconURL": "$BASE_URL/icon.png",
        "tintColor": "#1E5AA8",
        "category": "entertainment",
        "versions": [{
            "version": "$VERSION",
            "buildVersion": "$BUILD",
            "date": "$DATE",
            "localizedDescription": """$NOTES""" or "NeoClub $VERSION.",
            "downloadURL": "$BASE_URL/$IPA",
            "size": $SIZE,
            "minOSVersion": "$MIN_OS",
        }],
        "appPermissions": {"entitlements": [], "privacy": {}},
    }],
    "news": [],
}
json.dump(source, open(sys.argv[1], "w"), indent=2)
EOF

echo "Built $DIST/$IPA ($SIZE bytes), $DIST/icon.png and $DIST/source.json"
echo "Upload everything in $DIST/ to $BASE_URL/ and add $BASE_URL/source.json in AltStore."
