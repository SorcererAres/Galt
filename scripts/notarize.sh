#!/usr/bin/env bash
# 公证并装订 dist/Galt.app，使其双击即可打开（无 Gatekeeper「未验证开发者」拦截）。
#
# 前置（一次性）：用 App Store Connect API Key 存好 notarytool 凭据
#   xcrun notarytool store-credentials "galt-notary" \
#       --key AuthKey_XXXX.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
#   （或用 --apple-id/--password/--team-id 的 app 专用密码方式）
#
# 用法：bash scripts/notarize.sh
# 凭据 profile 名可用环境变量 GALT_NOTARY_PROFILE 覆盖（默认 galt-notary）。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Galt.app"
PROFILE="${GALT_NOTARY_PROFILE:-galt-notary}"

[[ -d "$APP" ]] || { echo "✗ 未找到 $APP，请先 bash scripts/package-app.sh"; exit 1; }

# 必须是 Developer ID + Hardened Runtime 才能通过公证
if ! codesign -dvvv "$APP" 2>&1 | grep -q "flags=.*runtime"; then
  echo "✗ 当前 .app 未启用 Hardened Runtime（多半是自签名/ad-hoc 包），公证会被拒。"
  echo "  请确认本机有 Developer ID 证书后重新 bash scripts/package-app.sh。"
  exit 1
fi

zip="$ROOT/dist/Galt-notarize.zip"
echo "▸ 压缩 .app…"
rm -f "$zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$zip"

echo "▸ 提交公证（profile: $PROFILE，等待结果，可能几分钟）…"
xcrun notarytool submit "$zip" --keychain-profile "$PROFILE" --wait

echo "▸ 装订票据到 .app…"
xcrun stapler staple "$APP"
rm -f "$zip"

echo "▸ 校验 Gatekeeper…"
spctl -a -vvv -t exec "$APP" 2>&1 | grep -iE "accepted|source" || true
echo "  ✓ 已公证并装订。可重新 bash scripts/make-dmg.sh 分发。"
