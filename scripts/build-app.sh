#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="dist/日序.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
iconset="$bin_dir/Rixu.iconset"
swift -module-cache-path "$bin_dir/ModuleCache" scripts/draw-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Rixu.icns"
cp "$bin_dir/Rixu" "$app/Contents/MacOS/Rixu"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --identifier com.rixu.menubar "$app"
codesign --verify --strict "$app"
print -r -- "$PWD/$app"
