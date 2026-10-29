#!/bin/zsh
# Re-takes the demo screenshots in one language (default English) on the iPhone simulator, in demo mode.
# Uses the DEBUG jump arguments of HomeView (-uiScreen/-uiScenario/-uiStep) and the fast replay.
#
#   ./scripts/screenshots.sh            # English → docs/screenshots/v6-en-*.png
#   LANG_CODE=de ./scripts/screenshots.sh
set -euo pipefail

ROOT=${0:A:h:h}
LANG_CODE="${LANG_CODE:-en}"
OUT="$ROOT/docs/screenshots"
DERIVED="${TMPDIR:-/tmp}/repair-assistant-demo-build"
UDID=$(xcrun simctl list devices available | grep -F "iPhone 17 Pro (" | head -1 | grep -oE '[A-F0-9-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild -project "$ROOT/ios/RepairAssistant.xcodeproj" -scheme RepairAssistant -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" build -quiet
APP=$(find "$DERIVED/Build/Products" -name RepairAssistant.app -path "*iphonesimulator*" | head -1)
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null || true

shot() {  # name, wait seconds, launch args…
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "($LANG_CODE)" -fastReplay YES "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/v6-$LANG_CODE-$name.png" >/dev/null
  echo "v6-$LANG_CODE-$name.png"
}

shot home 7
shot settings 4 -uiScreen settings
shot shopping 16 -uiScreen shopping -uiScenario textile_tear
shot completion 16 -uiScreen completion -uiScenario textile_tear
shot analysis-agent 8  -uiScreen analysis -uiScenario textile_tear -recoveryTrace YES
shot diagnosis-jeans 12 -uiScreen diagnosis -uiScenario textile_tear -recoveryTrace NO
shot diagnosis-sweater 12 -uiScreen diagnosis -uiScenario textile_hole
shot decision-slider 16 -uiScreen decision -uiScenario textile_tear
shot guide-darning 24 -uiScreen guide -uiScenario textile_tear -uiStep 4
shot guide-solder 22 -uiScreen guide -uiScenario platine -uiStep 3
shot guide-shoe 22 -uiScreen guide -uiScenario shoe_sole -uiStep 2
shot blocked-battery 10 -uiScreen diagnosis -uiScenario battery_jacket
