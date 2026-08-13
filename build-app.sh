#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/DictateMac.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
swift build -c release --product DictateMac

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/DictateMac" "$CONTENTS/MacOS/DictateMac"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod 755 "$CONTENTS/MacOS/DictateMac"
plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

printf 'Built %s\n' "$APP"
