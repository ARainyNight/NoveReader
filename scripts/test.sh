#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/module-cache
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -target arm64-apple-macos14.0 -sdk "$(xcrun --sdk macosx26.5 --show-sdk-path)" \
    -module-cache-path "$PWD/build/module-cache" \
    NovelReader/Services/*.swift NovelReader/Reader/*.swift \
    NovelReader/Utilities/*.swift NovelReaderTests/*.swift \
    NovelReader/Models/*.swift \
    NovelReader/Views/*.swift \
    -o build/NovelReaderTests
build/NovelReaderTests "$@"
