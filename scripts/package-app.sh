#!/usr/bin/env bash
# 把 SwiftPM 可执行文件打包成可分发的 Galt.app（含动态框架嵌入 + ad-hoc 签名）。
#
# 用法：bash scripts/package-app.sh
# 产物：dist/Galt.app
#
# 前置：Vendor/ 框架就绪（必要时先跑 scripts/fetch-vendor.sh）。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Galt.app"
CONTENTS="$APP/Contents"

echo "▸ release 构建…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "▸ 组装 .app 骨架…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp "$BIN/Galt" "$CONTENTS/MacOS/Galt"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# 可选 App 图标（存在才拷）
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

echo "▸ 嵌入动态依赖到 Frameworks/…"
cp -R "$BIN/whisper.framework" "$CONTENTS/Frameworks/"
cp "$BIN"/libonnxruntime.*.dylib "$CONTENTS/Frameworks/"

# 可执行文件已有 @loader_path（=MacOS/），再补 Frameworks 的标准 rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/Galt" 2>/dev/null || true

# 签名身份：优先环境变量 → Developer ID Application（可公证）→ 自签「Galt Dev Signing」→ ad-hoc。
# 用稳定身份签名，TCC/钥匙串授权才能跨重打包持久（ad-hoc 的 cdhash 每次都变会作废授权）。
IDENTITY="${GALT_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if did=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application"); then
    IDENTITY="$(echo "$did" | sed -E 's/.*"(.*)".*/\1/')"
  elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Galt Dev Signing"; then
    IDENTITY="Galt Dev Signing"
  else
    IDENTITY="-"
  fi
fi

ENTITLEMENTS="$ROOT/Resources/Galt.entitlements"
# Developer ID 需开启 Hardened Runtime + 安全时间戳（公证前提）；自签/ad-hoc 不需要也不支持
EXTRA=()
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  EXTRA=(--options runtime --timestamp --entitlements "$ENTITLEMENTS")
  echo "▸ 签名（$IDENTITY，Hardened Runtime，可公证）…"
elif [[ "$IDENTITY" == "-" ]]; then
  echo "▸ 签名（ad-hoc，授权不会持久）…"
else
  echo "▸ 签名（$IDENTITY，自签名，授权可持久）…"
fi

# 先签嵌套的框架/库，再签主程序（带 entitlements）与 bundle
# ${EXTRA[@]+...} 安全展开空数组，兼容 macOS 自带 bash 3.2 的 set -u
codesign --force ${EXTRA[@]+"${EXTRA[@]}"} -s "$IDENTITY" "$CONTENTS/Frameworks/whisper.framework"
for dy in "$CONTENTS/Frameworks/"libonnxruntime.*.dylib; do
  codesign --force ${EXTRA[@]+"${EXTRA[@]}"} -s "$IDENTITY" "$dy"
done
codesign --force ${EXTRA[@]+"${EXTRA[@]}"} -s "$IDENTITY" "$CONTENTS/MacOS/Galt"
codesign --force ${EXTRA[@]+"${EXTRA[@]}"} -s "$IDENTITY" "$APP"

echo "▸ 校验…"
codesign --verify --deep --strict "$APP" && echo "  ✓ 签名有效"
ver="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$CONTENTS/Info.plist")"
echo ""
echo "完成：dist/Galt.app（v$ver）"
echo "运行：open dist/Galt.app   首次右键→打开 以绕过未公证提示"
