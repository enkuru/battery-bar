#!/bin/bash
# Builds build/BatteryBar.app with the Command Line Tools; no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

app=build/BatteryBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos14" Sources/*.swift -o "$app/Contents/MacOS/BatteryBar"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
