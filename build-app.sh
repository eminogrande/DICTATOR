#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/DICTATOR.app"
CONTENTS="$APP/Contents"
BRAIN_ROOT="${NUANCED_BRAIN_ROOT:-$ROOT/../nuanced-mcp-typescript}"
BRAIN="$CONTENTS/Resources/Brain"
REQUIREMENT='=designated => identifier "de.emin.DictateMac"'

cd "$ROOT"
swift build -c release --product DictateMac
(cd "$BRAIN_ROOT" && npm run build)

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$BRAIN"
cp "$ROOT/.build/release/DictateMac" "$CONTENTS/MacOS/DictateMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/DICTATOR.icns" "$CONTENTS/Resources/DICTATOR.icns"
cp "$ROOT/Resources/DICTATOR-menu@2x.png" "$CONTENTS/Resources/DICTATOR-menu@2x.png"
cp "$(command -v node)" "$BRAIN/node"
ditto "$BRAIN_ROOT/dist" "$BRAIN/dist"
ditto "$BRAIN_ROOT/node_modules" "$BRAIN/node_modules"
cp "$BRAIN_ROOT/package.json" "$BRAIN/package.json"
chmod 755 "$CONTENTS/MacOS/DictateMac" "$BRAIN/node"
"$BRAIN/node" "$BRAIN/dist/brain-cli.js" stats >/dev/null
plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - --requirements "$REQUIREMENT" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d -r- "$APP" 2>&1 | grep -F 'designated => identifier "de.emin.DictateMac"' >/dev/null

printf 'Built %s with bundled Brain and stable designated requirement\n' "$APP"
