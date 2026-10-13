#!/bin/bash
# Builds and packages WakeMate into a redistributable ZIP archive.
# Usage: ./Scripts/package-release.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Building WakeMate release bundle..."
"$SCRIPT_DIR/build-app.sh" release

echo "==> Creating release archive in build/WakeMate.zip..."
cd "$ROOT_DIR/build"
rm -f WakeMate.zip WakeMate.zip.sha256
zip -q -r -y WakeMate.zip WakeMate.app

shasum -a 256 WakeMate.zip > WakeMate.zip.sha256
CHECKSUM=$(cat WakeMate.zip.sha256 | awk '{print $1}')

echo "✓ Successfully packaged WakeMate.zip"
echo "  Archive:  $ROOT_DIR/build/WakeMate.zip"
echo "  SHA-256:  $CHECKSUM"
