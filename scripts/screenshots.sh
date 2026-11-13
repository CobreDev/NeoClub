#!/bin/zsh
# Takes the five AltStore listing screenshots on the iPhone 18 Pro simulator, with the screenshot demo mode
# (NeoClub/App/DemoMode.swift, compiled only with -DSCREENSHOT_DEMO): no listening progress anywhere, #001 Whit's
# Flop in the player, nothing sent to the account.
#
#   scripts/screenshots.sh
#
# Needs the simulator to be signed in once (open it in DeviceHub, tap Sign In, pick the profile yourself; the
# sign-in persists in the simulator). Writes screenshots/1-home.png ... 5-now-playing.png at 1206x2622.
set -euo pipefail
cd "${0:A:h}/.."

UDID=${SIM_UDID:-6A557932-ABCA-4470-822F-A0ABCA3DED70}   # iPhone 18 Pro, iOS 27.2
APP=build/sim/Build/Products/Debug-iphonesimulator/NeoClub.app
OUT=screenshots
mkdir -p "$OUT"

xcodegen generate -q
xcodebuild -project NeoClub.xcodeproj -scheme NeoClub -configuration Debug -destination "id=$UDID" \
    -derivedDataPath build/sim OTHER_SWIFT_FLAGS='$(inherited) -DSCREENSHOT_DEMO' build -quiet
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl terminate "$UDID" dev.cobre.aioclub 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi

shot() {   # name, screen, seconds to wait
    xcrun simctl terminate "$UDID" dev.cobre.aioclub 2>/dev/null || true
    xcrun simctl launch "$UDID" dev.cobre.aioclub -syncProgress NO -demoScreen "$2" >/dev/null
    sleep "$3"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1
    echo "  $OUT/$1.png"
}
shot 1-home        home       14
shot 2-browse      browse     16
shot 3-album       album      18
shot 4-episode      episode    18
shot 5-now-playing nowplaying 20

xcrun simctl status_bar "$UDID" clear
