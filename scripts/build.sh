#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/NovelReader.app/Contents/MacOS build/module-cache
sources=(NovelReader/**/*.swift)
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -target arm64-apple-macos14.0 -sdk "$(xcrun --sdk macosx26.5 --show-sdk-path)" \
    -module-cache-path "$PWD/build/module-cache" \
    -module-name NovelReader "${sources[@]}" \
    -o build/NovelReader.app/Contents/MacOS/NovelReader
cp NovelReader/Info.plist build/NovelReader.app/Contents/Info.plist
codesign --force --sign - --entitlements NovelReader/NovelReader.entitlements \
    build/NovelReader.app
print "Built: $PWD/build/NovelReader.app"
