#!/usr/bin/env bash
# Builds build/PlayStatus.app. Needs the Xcode Command Line Tools (xcode-select --install).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PlayStatus"
CONFIGURATION="${CONFIGURATION:-release}"
APP="build/$APP_NAME.app"

swift build -c "$CONFIGURATION" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run the app on the Mac that built it.
codesign --force --sign - "$APP"

echo "Fertig: $APP"
echo "Starten mit: open \"$APP\""
