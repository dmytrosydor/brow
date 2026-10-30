#!/bin/sh
# Builds brow.app and installs it into /Applications, then starts it.
# Usage: scripts/install.sh [version]
set -eu

cd "$(dirname "$0")/.."
scripts/build-app.sh "${1:-0.2.0}"

pkill -x brow 2>/dev/null || true
rm -rf /Applications/brow.app
ditto build/brow.app /Applications/brow.app
open /Applications/brow.app
echo "installed /Applications/brow.app"
echo "Right-click the notch and choose \"Connect to all Claude sessions…\" if you have not yet."
