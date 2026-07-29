#!/usr/bin/env bash
# Упаковка Linux-сборки Flutter в один файл AppImage (двойной клик → запуск)
set -e

APPDIR=AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
cp -r build/linux/x64/release/bundle/* "$APPDIR/usr/bin/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:$LD_LIBRARY_PATH"
exec "$HERE/usr/bin/bitaps_vpn" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/bitaps.desktop" <<'EOF'
[Desktop Entry]
Name=bitaps VPN
Exec=bitaps_vpn
Icon=bitaps
Type=Application
Categories=Network;
EOF

cp assets/icon.png "$APPDIR/bitaps.png"

# appimagetool закреплён по SHA-256, как и движок xray: «continuous» — подвижная цель, и
# подменённый упаковщик вшил бы чужой код в раздаваемый AppImage. Ломаемся при смене апстрима —
# это и есть точка проверки: обновить хэш осознанно, посмотрев, что поменялось у AppImage.
APPIMAGETOOL_SHA256="a6d71e2b6cd66f8e8d16c37ad164658985e0cf5fcaa950c90a482890cb9d13e0"
wget -q "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
echo "$APPIMAGETOOL_SHA256  appimagetool" | sha256sum -c -
chmod +x appimagetool
ARCH=x86_64 ./appimagetool --appimage-extract-and-run "$APPDIR" bitaps-x86_64.AppImage

ls -la bitaps-x86_64.AppImage
