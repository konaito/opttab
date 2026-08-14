#!/bin/bash
# 公証済みuniversalバイナリを作ってGitHub Releaseに添付する
# 前提: xcrun notarytool store-credentials "AC_PASSWORD" --apple-id <id> \
#         --team-id T79674CM55 --password <app用パスワード> 済み
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: notarize-release.sh <version e.g. 0.2.0>}

# Support/Info.plist のバージョンとタグを一致させる（doctorとformulaが同じ値を見る）
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    Support/Info.plist)
if [ "$PLIST_VERSION" != "$VERSION" ]; then
    echo "Support/Info.plist は $PLIST_VERSION だが引数は $VERSION。揃えること" >&2
    exit 1
fi

swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/OptTab
lipo -info "$BIN"

IDENTITY=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
[ -n "$IDENTITY" ] || { echo "Developer ID Application証明書が見つからない"; exit 1; }

STAGE=build/stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BIN" "$STAGE/opttab"

# signing identifier は dev.konaito.opttab から変えてはならない。
# 変えるとTCCのcsreq検証に落ちて既存ユーザーの許可が飛ぶ。
codesign --force --options runtime -i dev.konaito.opttab \
    --sign "$IDENTITY" "$STAGE/opttab"
codesign --verify --strict --verbose=2 "$STAGE/opttab"

TARBALL="build/opttab-$VERSION-universal.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$STAGE" opttab

# 単体Mach-Oはzipに入れて提出する（notarytoolはtar.gzを受け付けない）
ZIP="build/opttab-$VERSION-notarize.zip"
rm -f "$ZIP"
ditto -c -k "$STAGE/opttab" "$ZIP"

echo "notarizing (数分かかる)..."
xcrun notarytool submit "$ZIP" --keychain-profile AC_PASSWORD --wait

# 単体バイナリには stapler staple できないので貼らない。
# Homebrewのcurlはquarantineを付けないため実行時検証には影響しない。

echo "sha256:"
shasum -a 256 "$TARBALL"
gh release upload "v$VERSION" "$TARBALL" --clobber
echo "uploaded: v$VERSION"
