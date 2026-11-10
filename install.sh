#!/bin/bash
# Builds BatteryBar, replaces the copy in /Applications and opens it. The login item points at that copy.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
pkill -x BatteryBar || true
ditto build/BatteryBar.app /Applications/BatteryBar.app
open /Applications/BatteryBar.app
