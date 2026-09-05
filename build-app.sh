#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${DICTATOR_BUILD_APP:-$ROOT/dist/DICTATOR.app}"
CONTENTS="$APP/Contents"
BRAIN_ROOT="${NUANCED_BRAIN_ROOT:-$ROOT/../nuanced-mcp-typescript}"
BRAIN="$CONTENTS/Resources/Brain"
REQUIREMENT='=designated => identifier "de.emin.DictateMac"'

cd "$ROOT"
SECRET_ENV=()
while IFS='=' read -r name _; do
  case "$name" in
    *KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*CREDENTIAL*) SECRET_ENV+=("-u" "$name") ;;
  esac
done < <(/usr/bin/env)
/usr/bin/env "${SECRET_ENV[@]}" swift build -c release --product DictateMac
(cd "$BRAIN_ROOT" && npm run build)

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$BRAIN"
cp "$ROOT/.build/release/DictateMac" "$CONTENTS/MacOS/DictateMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
ditto "$ROOT/.build/release/DictateMac_DictateMac.bundle" "$CONTENTS/Resources/DictateMac_DictateMac.bundle"
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
