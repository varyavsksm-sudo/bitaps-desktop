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

wget -q "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
chmod +x appimagetool
ARCH=x86_64 ./appimagetool --appimage-extract-and-run "$APPDIR" bitaps-x86_64.AppImage

ls -la bitaps-x86_64.AppImage
