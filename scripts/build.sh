#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-python3}"
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info[:2] in ((3,12),(3,13)) else "wisprM requires Python 3.12 or 3.13. Set PYTHON=/path/to/python3.12.")'
xcrun swift build -c release
BIN="$(xcrun swift build -c release --show-bin-path)"
APP="$PWD/dist/wisprM.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/wisprM" "$APP/Contents/MacOS/wisprM"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/runtime"
cp runtime/*.py runtime/requirements*.txt runtime/models.lock.json runtime/setup-runtime.sh "$APP/Contents/Resources/runtime/"
xcrun swift scripts/make-icon.swift "$APP/Contents/Resources"
"$PYTHON" -c 'import pathlib,shutil; p=pathlib.Path("dist/wisprM.app/Contents/Resources/runtime/__pycache__"); shutil.rmtree(p,ignore_errors=True)'
codesign --force --sign - --entitlements Resources/entitlements.plist "$APP"
codesign --verify --strict "$APP"
"$PYTHON" scripts/check-bundle.py "$APP"
echo "Built $APP"
