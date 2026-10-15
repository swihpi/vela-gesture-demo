#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/outputs/Vela.app"
DESTINATION="/Applications/Vela.app"
if [ ! -d "$SOURCE" ]; then echo 'Build Vela before installing: ./script/build_and_run.sh --build' >&2; exit 1; fi
/usr/bin/codesign --verify --strict "$SOURCE"
if [ -d "$DESTINATION" ]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")"
  if [ "$EXISTING_ID" != 'com.swi.vela' ]; then echo 'A different app named Vela is already installed; refusing to replace it.' >&2; exit 1; fi
fi
/bin/ps -p $$ -o pid= >/dev/null
if /usr/bin/pgrep -x Vela >/dev/null; then
  /usr/bin/pkill -x Vela
  for attempt in 1 2 3 4 5; do
    if ! /usr/bin/pgrep -x Vela >/dev/null; then break; fi
    sleep 1
  done
  if /usr/bin/pgrep -x Vela >/dev/null; then echo 'Vela is still running; installation stopped.' >&2; exit 1; fi
fi
STAGE="$(mktemp -d /Applications/.vela-install.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$SOURCE" "$STAGE/Vela.app"
/usr/bin/codesign --verify --strict "$STAGE/Vela.app"
BACKUP="$PWD/work/InstalledVela.previous.backup"
if [ -d "$BACKUP" ]; then rm -rf "$BACKUP"; fi
if [ -d "$DESTINATION" ]; then mv "$DESTINATION" "$BACKUP"; fi
if ! mv "$STAGE/Vela.app" "$DESTINATION"; then
  if [ -d "$BACKUP" ]; then mv "$BACKUP" "$DESTINATION"; fi
  exit 1
fi
/usr/bin/open "$DESTINATION"
echo "Installed and launched $DESTINATION"
