#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
output_dir="${RIXU_BUILD_OUTPUT:-$PWD/dist}"
mkdir -p "$output_dir"
output_dir="${output_dir:A}"
staging="$(mktemp -d "$output_dir/.rixu-app.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
app="$staging/日序.app"
swift_flags=()
public_key="${RIXU_OTA_PUBLIC_KEY:-}"
if [[ -n "$public_key" ]]; then
    if [[ ! "$public_key" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
        print -u2 -- "RIXU_OTA_PUBLIC_KEY 必须是 Base64 格式的 Sparkle 公钥。"
        exit 1
    fi
    sdk="$(/bin/zsh scripts/prepare-sparkle.sh)"
    swift_flags=(-Xswiftc -DRIXU_OTA -Xswiftc -F -Xswiftc "$sdk"
                 -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
fi
swift build -c release "${swift_flags[@]}"
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
iconset="$bin_dir/Rixu.iconset"
swift -module-cache-path "$bin_dir/ModuleCache" scripts/draw-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Rixu.icns"
cp "$bin_dir/Rixu" "$app/Contents/MacOS/Rixu"
cp scripts/Info.plist "$app/Contents/Info.plist"
if [[ -n "$public_key" ]]; then
    mkdir "$app/Contents/Frameworks"
    /usr/bin/ditto "$sdk/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
    cp "$sdk/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
    /usr/libexec/PlistBuddy -c "Add SUPublicEDKey string $public_key" \
        -c 'Add SUFeedURL string https://github.com/Merenguelkl/rixu/releases/latest/download/appcast.xml' \
        -c 'Add SURequireSignedFeed bool true' \
        -c 'Add SUVerifyUpdateBeforeExtraction bool true' \
        -c 'Add SUEnableAutomaticChecks bool true' \
        -c 'Add SUAutomaticallyUpdate bool false' "$app/Contents/Info.plist"
fi
codesign --force --sign - --identifier com.rixu.menubar "$app"
codesign --verify --deep --strict "$app"
rm -rf -- "$output_dir/日序.app"
mv "$app" "$output_dir/日序.app"
print -r -- "$output_dir/日序.app"
