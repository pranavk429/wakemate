#!/bin/bash
# Builds WakeMate with SwiftPM and wraps it into an ad-hoc signed .app bundle.
# Usage: ./Scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/WakeMate.app"

cd "$ROOT"
swift build -c "$CONFIG" --product WakeMate
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$BIN_DIR/WakeMate" "$APP/Contents/MacOS/WakeMate"
/bin/cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature: enough for a personal, locally built app (no notarization).
/usr/bin/codesign --force --sign - --timestamp=none "$APP"

echo "✓ Built $APP"
echo "  Run:     open \"$APP\""
echo "  Install: cp -R \"$APP\" /Applications/"
