#!/usr/bin/env bash
# Скачать LibXray.xcframework (Xray-core для iOS/macOS, MIT) из релизов XTLS/libXray
# и разложить в ios/Frameworks/. Запуск: bash tools/fetch-libxray.sh [версия, напр. v26.7.11]
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:-}"
DEST=ios/Frameworks
mkdir -p "$DEST"

if [ -z "$VER" ]; then
  VER=$(curl -fsSL https://api.github.com/repos/XTLS/libXray/releases/latest | python3 -c "import sys,json;print(json.load(sys.stdin)['tag_name'])")
fi
echo "libXray $VER"
ASSET=$(curl -fsSL "https://api.github.com/repos/XTLS/libXray/releases/tags/$VER" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# cgo-сборка с modulemap — её Swift импортирует как модуль LibXray
cands = [a for a in d['assets'] if 'apple' in a['name'].lower() and a['name'].endswith('.zip')]
pref = [a for a in cands if 'cgo' in a['name'].lower()] or cands
if not pref: raise SystemExit('нет apple-артефакта в релизе ' + '$VER')
print(pref[0]['browser_download_url'])
")
echo "качаем: $ASSET"
curl -fSL "$ASSET" -o /tmp/libxray-apple.zip
unzip -o -q /tmp/libxray-apple.zip -d /tmp/libxray-apple
find /tmp/libxray-apple -name "LibXray.xcframework" -maxdepth 3 -type d | head -1 | xargs -I{} cp -R {} "$DEST/"
ls "$DEST/LibXray.xcframework" && echo "OK: $DEST/LibXray.xcframework"
echo "Теперь в Xcode: перетащи $DEST/LibXray.xcframework в таргет PacketTunnel (Embed & Sign)."
