#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

sdk="$(/bin/zsh scripts/prepare-sparkle.sh)"
account="rixu-release"
key_args=(--account "$account")
if [[ -n "${RIXU_OTA_KEY_FILE:-}" ]]; then
    : "${RIXU_OTA_PUBLIC_KEY:?指定私钥文件时也必须指定对应的 Sparkle 公钥。}"
    key_args=(--ed-key-file "$RIXU_OTA_KEY_FILE")
else
    RIXU_OTA_PUBLIC_KEY="$(<scripts/ota-public-key.txt)"
fi
export RIXU_OTA_PUBLIC_KEY

./scripts/build-dmg.sh
output_dir="${RIXU_BUILD_OUTPUT:-$PWD/dist}"
output_dir="${output_dir:A}"
app="$output_dir/日序.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(/usr/bin/lipo -archs "$app/Contents/MacOS/Rixu")"
archive="Rixu-${version}-${architecture}.zip"
staging="$(mktemp -d "$output_dir/.rixu-ota.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/$archive"
release_url="https://github.com/Merenguelkl/rixu/releases"
"$sdk/bin/generate_appcast" "${key_args[@]}" --maximum-deltas 0 \
    --download-url-prefix "$release_url/download/v$version/" \
    --full-release-notes-url "$release_url/tag/v$version" \
    --link "$release_url/tag/v$version" "$staging"
signature="$(/usr/bin/xmllint --xpath \
    'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$staging/appcast.xml")"
swift -module-cache-path "$PWD/.build/ModuleCache" scripts/verify-ota.swift \
    "$staging/appcast.xml" "$staging/$archive" "$signature" "$RIXU_OTA_PUBLIC_KEY"
mv -f "$staging/$archive" "$output_dir/$archive"
mv -f "$staging/appcast.xml" "$output_dir/appcast.xml"
print -r -- "$output_dir/$archive" "$output_dir/appcast.xml"
