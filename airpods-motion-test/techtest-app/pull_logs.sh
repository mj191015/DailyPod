#!/bin/bash
# Copies the app's Documents folder (all test logs) from the iPhone into ../summary/data/raw_logs
#
# Usage:  ./pull_logs.sh <BUNDLE_ID> [DEVICE]
set -euo pipefail
cd "$(dirname "$0")"
BUNDLE="${1:?usage: $0 <BUNDLE_ID> [DEVICE]}"
DEVICE="${2:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E ' connected ' | grep -v simulated \
           | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' | head -1 || true)
  [ -n "$DEVICE" ] || { echo "No connected iPhone found. Plug it in, unlock it, and pass its UDID as the 2nd argument."; exit 1; }
fi
DEST="../summary/data/raw_logs"
mkdir -p "$DEST"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" --source Documents --destination "$DEST"
echo "Logs copied to $(cd "$DEST" && pwd)"
