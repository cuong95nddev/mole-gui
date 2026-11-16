#!/bin/sh
# Build MoleDesk.app into build/.
#   scripts/bundle.sh                → this Mac's architecture
#   UNIVERSAL=1 scripts/bundle.sh    → arm64 + x86_64 universal binary (used by CI)
# Signing:
#   MOLEDESK_SIGN_ID="Developer ID Application: …" → signed for distribution
#     (hardened runtime + secure timestamp, as notarization requires).
#   Unset: signs with a Developer ID / Apple Development identity found in the
#     keychain, else ad hoc. A stable identity keeps the Full Disk Access grant
#     across rebuilds; ad hoc builds lose it every time.
# Prints the app's path.
set -eu
cd "$(dirname "$0")/.."

NAME="MoleDesk"
APP="build/$NAME.app"
VERSION=$(tr -d '[:space:]' < VERSION)

if [ "${UNIVERSAL:-0}" = 1 ]; then
  # `swift build --arch a --arch b` trips over SwiftTerm's build plugin, so
  # build each architecture and glue them together.
  for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0" >&2
  done
  mkdir -p build
  lipo -create -output "build/$NAME-universal" \
    ".build/arm64-apple-macosx/release/$NAME" \
    ".build/x86_64-apple-macosx/release/$NAME"
  BIN="build/$NAME-universal"
else
  swift build -c release >&2
  BIN="$(swift build -c release --show-bin-path)/$NAME"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>dev.cuong95nddev.moledesk</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

if [ -n "${MOLEDESK_SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$MOLEDESK_SIGN_ID" "$APP" >&2
else
  ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  [ -n "$ID" ] || ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')
  if [ -n "$ID" ]; then
    codesign --force --options runtime --sign "$ID" "$APP" >&2
    echo "signed with: $ID" >&2
  else
    codesign --force --sign - "$APP" >&2
    echo "no signing identity: ad hoc (Full Disk Access must be re-granted after each rebuild)" >&2
  fi
fi
echo "$APP"
