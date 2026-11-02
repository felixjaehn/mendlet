#!/bin/zsh
# One command for judges: build the iOS app and start it in demo mode on an iPhone simulator.
# Demo mode replays real, unedited Meta API responses (ios/RepairAssistant/Resources/LiveRecordings/),
# so no API key and no proxy are needed. Requires Xcode 27 and XcodeGen (`brew install xcodegen`).
#
#   ./scripts/run-demo.sh                  # Home screen, pick a scenario
#   ./scripts/run-demo.sh jeans_guide      # jump straight to the stitch-path step of the jeans tear
set -euo pipefail

ROOT=${0:A:h:h}
IOS="$ROOT/ios"
DERIVED="${TMPDIR:-/tmp}/repair-assistant-demo-build"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

command -v xcodegen >/dev/null && (cd "$IOS" && xcodegen generate >/dev/null)

UDID=$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | head -1 | grep -oE '[A-F0-9-]{36}' || true)
if [[ -z "$UDID" ]]; then   # fall back to the first available iPhone simulator
  UDID=$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1 | grep -oE '[A-F0-9-]{36}' || true)
fi
[[ -n "$UDID" ]] || { echo "No iPhone simulator found. Install one in Xcode › Settings › Components, or set DEVICE_NAME=…"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
open "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true

echo "Building (first build takes a few minutes)…"
xcodebuild -project "$IOS/RepairAssistant.xcodeproj" -scheme RepairAssistant \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" build -quiet

APP=$(find "$DERIVED/Build/Products" -name RepairAssistant.app -path "*iphonesimulator*" | head -1)
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

case "${1:-home}" in
  jeans_guide) xcrun simctl launch "$UDID" "$BUNDLE" -uiScreen guide -uiScenario textile_tear -uiStep 3 ;;
  home|*)      xcrun simctl launch "$UDID" "$BUNDLE" ;;
esac
echo "Running in demo mode with recorded Meta API responses."
