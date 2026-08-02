#!/bin/bash
# OptTabを.appにバンドルして ~/Applications に配置する
# --build-only: build/OptTab.app を作るだけ（インストール・プロセス停止をしない。Homebrew formula用）
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_ONLY=0
[ "${1:-}" = "--build-only" ] && BUILD_ONLY=1

swift build -c release

APP=build/OptTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/OptTab "$APP/Contents/MacOS/OptTab"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.konaito.opttab</string>
    <key>CFBundleName</key><string>OptTab</string>
    <key>CFBundleDisplayName</key><string>OptTab</string>
    <key>CFBundleExecutable</key><string>OptTab</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Apple Development証明書があればそれで署名（TCC権限がリビルドで飛びにくい）。
# 無ければad-hoc署名（リビルドごとに権限の再許可が必要になる）。
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

if [ "$BUILD_ONLY" = 1 ]; then
    echo "built: $APP"
    exit 0
fi

mkdir -p ~/Applications
# 起動中なら止めてから差し替え
pkill -x OptTab 2>/dev/null || true
rm -rf ~/Applications/OptTab.app
cp -R "$APP" ~/Applications/OptTab.app
echo "installed: ~/Applications/OptTab.app"
echo "launch:    open ~/Applications/OptTab.app"
