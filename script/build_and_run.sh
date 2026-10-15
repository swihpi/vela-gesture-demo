#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
swift build --disable-sandbox --product Vela
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
FINAL_APP="$PWD/outputs/Vela.app"
SIGNING_IDENTITY="${VELA_SIGNING_IDENTITY:-$(cat .vela-signing-identity 2>/dev/null || true)}"
if [ -z "$SIGNING_IDENTITY" ]; then
  echo 'Set VELA_SIGNING_IDENTITY to a valid code-signing certificate. Ad-hoc signing is disabled because it invalidates privacy approvals on rebuild.' >&2
  exit 1
fi
mkdir -p work
STAGE="$(mktemp -d "$PWD/work/vela-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Vela.app"
mkdir -p "$APP/Contents/Resources"
if [ -f "$FINAL_APP/Contents/Resources/Vela.icns" ]; then
  cp "$FINAL_APP/Contents/Resources/Vela.icns" "$APP/Contents/Resources/Vela.icns"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ ! -f "$APP/Contents/Resources/Vela.icns" ]; then
  ICONSET="$PWD/work/Vela.iconset"
  mkdir -p "$ICONSET"
  swift -module-cache-path "$PWD/.build/arm64-apple-macosx/debug/ModuleCache" script/make_icon.swift "$PWD/work/icon.png"
  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" work/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" work/icon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Vela.icns"
fi
cp "$BIN_DIR/Vela" "$APP/Contents/MacOS/Vela"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Vela</string>
<key>CFBundleIdentifier</key><string>com.swi.vela</string>
<key>CFBundleName</key><string>Vela</string>
<key>CFBundleIconFile</key><string>Vela</string>
<key>CFBundleDisplayName</key><string>Vela</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><false/>
<key>NSCameraUsageDescription</key><string>Vela uses your built-in camera to recognise your configured hand gestures and operate Zoom video and microphone controls. Frames are processed locally and never recorded.</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --identifier com.swi.vela "$APP"
/usr/bin/codesign --verify --strict "$APP"
# Never replace a signed bundle while an old process still maps its executable.
# A sandbox that cannot inspect processes must fail here rather than corrupt TCC identity.
/bin/ps -p $$ -o pid= >/dev/null
if PIDS="$(/usr/bin/pgrep -x Vela)"; then
  /usr/bin/pkill -x Vela
  for attempt in 1 2 3 4 5; do
    if ! /usr/bin/pgrep -x Vela >/dev/null; then break; fi
    sleep 1
  done
  if /usr/bin/pgrep -x Vela >/dev/null; then echo 'Vela is still running; refusing to replace its bundle.' >&2; exit 1; fi
else
  RESULT=$?
  if [ "$RESULT" -ne 1 ]; then echo 'Cannot inspect running Vela processes; refusing to publish.' >&2; exit 1; fi
fi
BACKUP="$PWD/work/Vela.previous.backup"
if [ -d "$BACKUP" ]; then rm -rf "$BACKUP"; fi
if [ -d "$FINAL_APP" ]; then mv "$FINAL_APP" "$BACKUP"; fi
if ! mv "$APP" "$FINAL_APP"; then
  if [ -d "$BACKUP" ]; then mv "$BACKUP" "$FINAL_APP"; fi
  exit 1
fi
APP="$FINAL_APP"
case "$MODE" in
  --build) ;;
  --install) ./script/install.sh ;;
  --verify) /usr/bin/open -n "$APP"; sleep 2; /usr/bin/pgrep -x Vela ;;
  --debug) lldb -- "$APP/Contents/MacOS/Vela" ;;
  --logs|--telemetry) /usr/bin/open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "Vela"' ;;
  run) /usr/bin/open -n "$APP" ;;
  *) echo "Usage: $0 [--build|--install|--verify|--debug|--logs|--telemetry]"; exit 2 ;;
esac
