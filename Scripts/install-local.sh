#!/bin/bash
# ローカル開発用: ビルド → 署名 → 固定パスへ配置 → LaunchAgent再起動
#
# launchd が起動する実体は $(brew --prefix)/var/opttab/opttab に固定する。
# TCC は非バンドルバイナリを実パスで識別するため、このパスを変えると
# アクセシビリティと画面収録の許可が失われる。
set -euo pipefail
cd "$(dirname "$0")/.."

PREFIX=$(brew --prefix)
DEST="$PREFIX/var/opttab"
LABEL=dev.konaito.opttab
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release
BIN=.build/release/OptTab

mkdir -p "$DEST"

# 実行中の Mach-O へ直接 cp すると ETXTBSY。先に止めて rm する。
# inode は変わるがパスは同じなので TCC の許可は維持される。
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$DEST/opttab"
cp "$BIN" "$DEST/opttab"

# signing identifier を変えると TCC の csreq 検証に落ちて許可が飛ぶ。
# Developer ID が無い環境では ad-hoc に落とすが、その場合は
# リビルドのたびに再許可が必要になる。
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime -i dev.konaito.opttab \
        --sign "$IDENTITY" "$DEST/opttab"
else
    echo "warning: Developer ID証明書が無いのでad-hoc署名にする。" >&2
    echo "         ビルドのたびにアクセシビリティの再許可が必要になる。" >&2
    codesign --force -i dev.konaito.opttab --sign - "$DEST/opttab"
fi

# brew services を使っていない開発環境向けに、無ければ plist を作る
if [ ! -f "$PLIST" ]; then
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DEST/opttab</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><array><string>Aqua</string></array>
</dict>
</plist>
PLIST_EOF
    echo "created: $PLIST"
fi

launchctl bootstrap "gui/$UID" "$PLIST"
echo "installed: $DEST/opttab"
"$DEST/opttab" --version
