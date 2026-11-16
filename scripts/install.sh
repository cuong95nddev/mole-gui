#!/bin/sh
# Build MoleDesk.app and install it into /Applications (replacing any previous copy).
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh >/dev/null
APP="/Applications/MoleDesk.app"
pkill -x MoleDesk 2>/dev/null || true
rm -rf "$APP"
ditto build/MoleDesk.app "$APP"
touch "$APP"  # make Finder/Dock pick up the new icon
echo "Installed: $APP"
