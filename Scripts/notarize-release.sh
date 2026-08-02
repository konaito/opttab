#!/bin/bash
# 公証済み配布zipを作ってGitHub Releaseに添付する
# 前提: xcrun notarytool store-credentials "AC_PASSWORD" --apple-id <id> --team-id T79674CM55 --password <app用パスワード> 済み
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: notarize-release.sh <version e.g. 0.1.0>}

./Scripts/bundle.sh --build-only
APP=build/OptTab.app

IDENTITY=$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')
[ -n "$IDENTITY" ] || { echo "Developer ID Application証明書が見つからない"; exit 1; }

# 配布用: Developer ID + hardened runtime で署名し直す
codesign --force --options runtime --sign "$IDENTITY" "$APP"

ZIP="build/OptTab-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "notarizing (数分かかる)..."
xcrun notarytool submit "$ZIP" --keychain-profile AC_PASSWORD --wait

# チケットをアプリに貼ってzipを作り直す
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "sha256:"
shasum -a 256 "$ZIP"
gh release upload "v$VERSION" "$ZIP" --clobber
echo "uploaded: v$VERSION"
