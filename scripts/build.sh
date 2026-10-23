#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift build -c release
BIN="$(xcrun swift build -c release --show-bin-path)"
APP="$PWD/dist/wisprM.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/wisprM" "$APP/Contents/MacOS/wisprM"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/runtime"
cp runtime/worker.py runtime/install-runtime.py runtime/requirements.txt runtime/setup-runtime.sh "$APP/Contents/Resources/runtime/"
xcrun swift scripts/make-icon.swift "$APP/Contents/Resources"
codesign --force --sign - --entitlements Resources/entitlements.plist "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"
