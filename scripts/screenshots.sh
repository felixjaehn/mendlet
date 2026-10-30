#!/bin/zsh
# Re-takes the demo screenshots in one language (default English) on the iPhone simulator, in demo mode.
# Uses the DEBUG jump arguments of HomeView (-uiScreen/-uiScenario/-uiStep) and the fast replay.
#
#   ./scripts/screenshots.sh            # English → docs/screenshots/v8-en-*.png
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
xcrun simctl launch "$UDID" "$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")" >/dev/null; sleep 4
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 2>/dev/null || true

shot() {  # name, wait seconds, launch args…
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" -AppleLanguages "($LANG_CODE)" -fastReplay YES "$@" >/dev/null
  sleep "$wait"
  rm -f "$OUT/v8-$LANG_CODE-$name.png"   # simctl cannot overwrite an existing PNG (error 513)
  xcrun simctl io "$UDID" screenshot "$OUT/v8-$LANG_CODE-$name.png" >/dev/null
  echo "v8-$LANG_CODE-$name.png"
}

ONLY="${ONLY:-}"   # ONLY="home project" re-takes just those shots
run() { [[ -z "$ONLY" || " $ONLY " == *" $1 "* ]] && shot "$@" || true; }

xcrun simctl ui "$UDID" appearance light
run home 6 -uiScreen home
run home-done 6 -uiScreen home -uiTab done
run project 8 -uiScreen project
run project-done 8 -uiScreen projectDone
run scan 6 -uiScreen scan
run settings 4 -uiScreen settings
run analysis-sweep 3 -uiScreen analysis -uiScenario real_sweater
run analysis-reveal 5.8 -uiScreen analysis -uiScenario textile_tear
run analysis-agent 8 -uiScreen analysis -uiScenario textile_tear -recoveryTrace YES
run finding-sweater 14 -uiScreen diagnosis -uiScenario real_sweater
run finding-jeans 14 -uiScreen diagnosis -uiScenario textile_tear -recoveryTrace NO
run finding-holes 14 -uiScreen diagnosis -uiScenario textile_hole
run finding-sole 14 -uiScreen diagnosis -uiScenario real_sole
run verdict-repair 18 -uiScreen decision -uiScenario real_sweater
run verdict-repaired 20 -uiScreen decision -uiScenario real_sweater -uiRepaired YES
run verdict-repair-jeans 18 -uiScreen decision -uiScenario textile_tear
run verdict-pro 18 -uiScreen decision -uiScenario real_sole
run verdict-replace 18 -uiScreen decision -uiScenario worn_shirt
run checklist 18 -uiScreen checklist -uiScenario textile_tear
run guide-sweater 22 -uiScreen guide -uiScenario real_sweater -uiStep 2
run guide-darning 24 -uiScreen guide -uiScenario textile_tear -uiStep 4
run guide-solder 22 -uiScreen guide -uiScenario platine -uiStep 3
run guide-shoe 22 -uiScreen guide -uiScenario shoe_sole -uiStep 2
run completion 22 -uiScreen completion -uiScenario textile_tear
run block-battery 16 -uiScreen diagnosis -uiScenario battery_jacket
run block-helmet 16 -uiScreen diagnosis -uiScenario helmet
xcrun simctl ui "$UDID" appearance dark
run home-dark 6 -uiScreen home
run finding-sweater-dark 14 -uiScreen diagnosis -uiScenario real_sweater
run verdict-repair-dark 18 -uiScreen decision -uiScenario real_sweater
run checklist-dark 18 -uiScreen checklist -uiScenario real_sweater
run guide-sweater-dark 22 -uiScreen guide -uiScenario real_sweater -uiStep 2
run project-dark 8 -uiScreen project
xcrun simctl ui "$UDID" appearance light
