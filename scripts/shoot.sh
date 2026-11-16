#!/bin/bash
# Usage: scripts/shoot.sh <pane> <out.png> [wait]
# Opens build/MoleDesk.app on a pane and captures its window.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x MoleDesk 2>/dev/null || true; sleep 0.5
open -n build/MoleDesk.app --args -pane "$1"
sleep "${3:-5}"
osascript -e 'tell application "MoleDesk" to activate' >/dev/null 2>&1 || true; sleep 1
WID=$(swift -e 'import CoreGraphics; let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]; for w in l where (w["kCGWindowOwnerName"] as? String) == "MoleDesk" && (w["kCGWindowLayer"] as? Int) == 0 { print(w["kCGWindowNumber"]!); break }')
screencapture -x -o -l "$WID" "$2"
