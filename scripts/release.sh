#!/bin/sh
# Build a universal MoleDesk.app and pack it in a DMG (with an Applications
# link to drag it onto) for a GitHub release.
#   scripts/release.sh [OUT_DIR]      default: dist
# Prints the DMG's path.
# For a DMG that opens without Gatekeeper warnings set MOLEDESK_SIGN_ID to a
# "Developer ID Application: ..." identity and MOLEDESK_NOTARY_PROFILE to a
# notarytool keychain profile (`xcrun notarytool store-credentials`): the app
# and the DMG are then signed, notarized and stapled (MOLEDESK_NOTARY_KEYCHAIN:
# the keychain holding that profile, if not the default one).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/dist"}
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
NAME="MoleDesk"

UNIVERSAL=1 "$ROOT/scripts/bundle.sh" >/dev/null
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/dmg"
ditto "$ROOT/build/$NAME.app" "$STAGE/dmg/$NAME.app"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$MOLEDESK_NOTARY_PROFILE" \
    ${MOLEDESK_NOTARY_KEYCHAIN:+--keychain "$MOLEDESK_NOTARY_KEYCHAIN"} --wait >&2
}
if [ -n "${MOLEDESK_NOTARY_PROFILE:-}" ]; then
  # The app gets its own ticket so it opens offline once copied out of the DMG.
  ditto -c -k --keepParent "$STAGE/dmg/$NAME.app" "$STAGE/app.zip"
  notarize "$STAGE/app.zip"
  xcrun stapler staple "$STAGE/dmg/$NAME.app" >&2
fi
ln -s /Applications "$STAGE/dmg/Applications"

mkdir -p "$OUT"
DMG="$OUT/MoleDesk-$VERSION-macos-universal.dmg"
rm -f "$DMG"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE/dmg" -fs HFS+ -format UDZO "$DMG" >/dev/null
if [ -n "${MOLEDESK_SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$MOLEDESK_SIGN_ID" "$DMG" >&2
fi
if [ -n "${MOLEDESK_NOTARY_PROFILE:-}" ]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG" >&2
fi
echo "$DMG"
