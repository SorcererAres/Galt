#!/usr/bin/env bash
# 获取并组装本地引擎所需的二进制框架（不入库，按需下载）。
#
# 用法：bash scripts/fetch-vendor.sh
# 幂等：已存在的框架默认跳过，加 --force 重新下载。
#
# 产物：
#   Vendor/sherpa-onnx.xcframework   sherpa-onnx 静态库（含 CSherpaOnnx modulemap）
#   Vendor/onnxruntime.xcframework   onnxruntime 动态库（由 dylib 现场打包）
#   Vendor/opus.xcframework          libopus 静态库（来自 Homebrew opus，纯链接产物）
#
# 注：Vendor/whisper.xcframework 直接随仓库提供，本脚本不处理。
# 注：opus 步骤依赖 Homebrew，需先 `brew install opus`（CI 的 macOS runner 自带 brew）。

set -euo pipefail

SHERPA_VER="1.13.3"
ORT_VER="1.24.4"
BASE="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VER}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="${ROOT}/Vendor"
FORCE="${1:-}"
mkdir -p "$VENDOR"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- sherpa-onnx.xcframework（macOS 静态库 + modulemap）----
if [[ "$FORCE" == "--force" || ! -d "$VENDOR/sherpa-onnx.xcframework" ]]; then
  echo "▸ 下载 sherpa-onnx v${SHERPA_VER} macOS 静态框架…"
  curl -fL -o "$tmp/sherpa.tar.bz2" \
    "${BASE}/sherpa-onnx-v${SHERPA_VER}-macos-xcframework-static.tar.bz2"
  tar xjf "$tmp/sherpa.tar.bz2" -C "$tmp"
  rm -rf "$VENDOR/sherpa-onnx.xcframework"
  mv "$tmp/sherpa-onnx-v${SHERPA_VER}-macos-xcframework-static/sherpa-onnx.xcframework" \
     "$VENDOR/sherpa-onnx.xcframework"

  # SPM 需要 modulemap 才能让 Swift import C-API
  hdr="$VENDOR/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers"
  cat > "$hdr/module.modulemap" <<'EOF'
module CSherpaOnnx {
    header "sherpa-onnx/c-api/c-api.h"
    export *
}
EOF
  echo "  ✓ Vendor/sherpa-onnx.xcframework"
else
  echo "▸ sherpa-onnx.xcframework 已存在，跳过（--force 可重下）"
fi

# ---- onnxruntime.xcframework（由动态库打包）----
if [[ "$FORCE" == "--force" || ! -d "$VENDOR/onnxruntime.xcframework" ]]; then
  echo "▸ 下载 onnxruntime ${ORT_VER}（osx-arm64）…"
  curl -fL -o "$tmp/ort.tar.bz2" \
    "${BASE}/sherpa-onnx-v${SHERPA_VER}-onnxruntime-${ORT_VER}-osx-arm64-shared.tar.bz2"
  tar xjf "$tmp/ort.tar.bz2" -C "$tmp"
  dylib="$tmp/sherpa-onnx-v${SHERPA_VER}-onnxruntime-${ORT_VER}-osx-arm64-shared/lib/libonnxruntime.${ORT_VER}.dylib"
  rm -rf "$VENDOR/onnxruntime.xcframework"
  xcodebuild -create-xcframework -library "$dylib" -output "$VENDOR/onnxruntime.xcframework" >/dev/null
  echo "  ✓ Vendor/onnxruntime.xcframework"
else
  echo "▸ onnxruntime.xcframework 已存在，跳过（--force 可重下）"
fi

# ---- opus.xcframework（libopus 静态库，来自 Homebrew opus，纯链接产物）----
# 仅打包 libopus.a；Swift 侧通过 Sources/COpusShim（随仓库的 C shim + opus 头）调用。
if [[ "$FORCE" == "--force" || ! -d "$VENDOR/opus.xcframework" ]]; then
  echo "▸ 打包 libopus（来自 Homebrew opus）…"
  if ! command -v brew >/dev/null 2>&1; then
    echo "  ✗ 需要 Homebrew：先安装 brew，再执行 brew install opus" >&2
    exit 1
  fi
  if ! opus_prefix="$(brew --prefix opus 2>/dev/null)" || [[ ! -f "$opus_prefix/lib/libopus.a" ]]; then
    echo "  ✗ 未找到 libopus.a：请先执行 brew install opus" >&2
    exit 1
  fi
  rm -rf "$VENDOR/opus.xcframework"
  xcodebuild -create-xcframework -library "$opus_prefix/lib/libopus.a" \
    -output "$VENDOR/opus.xcframework" >/dev/null
  echo "  ✓ Vendor/opus.xcframework"
else
  echo "▸ opus.xcframework 已存在，跳过（--force 可重下）"
fi

echo "完成。现在可执行：swift build"
