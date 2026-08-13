#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/DICTATOR.app"
CONTENTS="$APP/Contents"
REQUIREMENT='=designated => identifier "de.emin.DictateMac"'

cd "$ROOT"
swift build -c release --product DictateMac

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/DictateMac" "$CONTENTS/MacOS/DictateMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/DICTATOR.icns" "$CONTENTS/Resources/DICTATOR.icns"
cp "$ROOT/Resources/DICTATOR-menu@2x.png" "$CONTENTS/Resources/DICTATOR-menu@2x.png"
chmod 755 "$CONTENTS/MacOS/DictateMac"
plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - --requirements "$REQUIREMENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -F 'designated => identifier "de.emin.DictateMac"' >/dev/null

printf 'Built %s with stable designated requirement\n' "$APP"
