#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

./scripts/build-app.sh
app="dist/日序.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(/usr/bin/lipo -archs "$app/Contents/MacOS/Rixu")"
output="$PWD/dist/Rixu-${version}-${architecture}.dmg"

staging="$(mktemp -d "$PWD/.build/rixu-dmg.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
mkdir "$staging/content"
/usr/bin/ditto "$app" "$staging/content/日序.app"
/bin/ln -s /Applications "$staging/content/Applications"

/usr/bin/hdiutil create -srcfolder "$staging/content" -volname "日序 $version" \
    -format UDZO "$staging/install.dmg"
/usr/bin/hdiutil verify "$staging/install.dmg"
mv -f "$staging/install.dmg" "$output"
print -r -- "$output"
