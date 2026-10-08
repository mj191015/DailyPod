#!/bin/bash
# Builds the TechTest app for a connected iPhone, installs it and starts it.
#
# Usage:  ./build_and_install.sh <TEAM_ID> <BUNDLE_ID> [DEVICE | --build-only]
#   TEAM_ID    your Apple Developer team ID (Xcode > Settings > Accounts, 10 characters)
#   BUNDLE_ID  any id you own, e.g. com.yourname.techtest
#   DEVICE     UDID or name of the iPhone (default: the first connected physical iPhone)
#   --build-only   only build, do not install
# The signing values are passed on the command line; the project file is never modified.
set -euo pipefail
cd "$(dirname "$0")"

TEAM="${1:?usage: $0 <TEAM_ID> <BUNDLE_ID> [DEVICE | --build-only]}"
BUNDLE="${2:?usage: $0 <TEAM_ID> <BUNDLE_ID> [DEVICE | --build-only]}"
DEVICE="${3:-}"

xcodebuild -project AirPodsProMotion.xcodeproj -scheme AirPodsProMotion -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" build
APP="build/Build/Products/Debug-iphoneos/AirPodsProMotion.app"
echo "Built: $APP"
[ "$DEVICE" = "--build-only" ] && exit 0

if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E ' connected ' | grep -v simulated \
           | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' | head -1 || true)
  [ -n "$DEVICE" ] || { echo "No connected iPhone found. Plug it in, unlock it, and pass its UDID as the 3rd argument."; exit 1; }
fi
echo "Device: $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE" || \
  echo "Installed. Unlock the iPhone and open the app by hand (and trust the developer in Settings > General > VPN & Device Management if asked)."
