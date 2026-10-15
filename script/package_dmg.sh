#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
DESTINATION="$ROOT/outputs/release"
mkdir -p "$DESTINATION" "$ROOT/work"
STAGE="$(mktemp -d "$ROOT/work/vela-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
swift build --disable-sandbox -c release --product Vela -Xswiftc -gnone -Xswiftc -file-prefix-map -Xswiftc "$ROOT=." -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
BIN="$(swift build --disable-sandbox -c release --show-bin-path)/Vela"
APP="$STAGE/content/Vela.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vela"
cp Support/Info.plist "$APP/Contents/Info.plist"
/usr/bin/strip -S "$APP/Contents/MacOS/Vela"
ICONSET="$STAGE/Vela.iconset"
mkdir -p "$ICONSET" "$ROOT/.build/icon-module-cache"
swift -module-cache-path "$ROOT/.build/icon-module-cache" script/make_icon.swift "$STAGE/icon.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$STAGE/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$STAGE/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Vela.icns"
# A public experimental build: no local certificate or private key is used.
# Ad-hoc code signing is not Apple Developer ID signing or notarisation.
codesign --force --sign - --identifier com.swi.vela "$APP"
codesign --verify --strict "$APP"
ln -s /Applications "$STAGE/content/Applications"
cp docs/INSTALL.md "$STAGE/content/Installation.txt"
DMG="$DESTINATION/Vela-$VERSION-apple-silicon.dmg"
hdiutil create -volname Vela -srcfolder "$STAGE/content" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd "$DESTINATION" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
echo "Created $DMG"
