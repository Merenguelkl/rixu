#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

version="2.10.1"
checksum="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
directory="$PWD/.build/sparkle-$version"
archive="$directory/Sparkle-$version.tar.xz"
sdk="$directory/sdk"

if [[ ! -d "$sdk/Sparkle.framework" ]]; then
    mkdir -p "$directory"
    staging="$(mktemp -d "$directory/staging.XXXXXX")"
    trap 'rm -rf -- "$staging"' EXIT
    if [[ ! -f "$archive" ]]; then
        /usr/bin/curl --fail --silent --show-error --location --http1.1 --retry 2 --max-time 120 \
            "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
            --output "$staging/archive.tar.xz"
        downloaded="$staging/archive.tar.xz"
    else
        downloaded="$archive"
    fi
    actual="$(/usr/bin/shasum -a 256 "$downloaded")"
    if [[ "${actual%% *}" != "$checksum" ]]; then
        print -u2 -- "Sparkle SHA-256 校验失败：$downloaded"
        exit 1
    fi
    mkdir "$staging/sdk"
    /usr/bin/tar -xf "$downloaded" -C "$staging/sdk"
    /usr/bin/codesign --verify --deep --strict "$staging/sdk/Sparkle.framework"
    mv "$staging/sdk" "$sdk"
fi

print -r -- "$sdk"
