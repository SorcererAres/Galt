#!/usr/bin/env bash
# 把 dist/Galt.app 打成可拖拽安装的 .dmg。
#
# 用法：bash scripts/make-dmg.sh
# 产物：dist/Galt-<版本>.dmg
#
# 若 dist/Galt.app 不存在，会先跑 package-app.sh。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Galt.app"
[[ -d "$APP" ]] || bash "$ROOT/scripts/package-app.sh"

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Galt-$VER.dmg"

stage="$(mktemp -d)"
cp -R "$APP" "$stage/"
ln -s /Applications "$stage/Applications"   # 拖拽到此即安装

echo "▸ 生成 $DMG …"
rm -f "$DMG"
hdiutil create -volname "Galt" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$stage"

echo "  ✓ $(du -h "$DMG" | cut -f1)  dist/Galt-$VER.dmg"
