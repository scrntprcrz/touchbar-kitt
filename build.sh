#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/TouchBarKITT.app"
executable="$app/Contents/MacOS/TouchBarKITT"
arch="$(uname -m)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Se requiere macOS y Xcode Command Line Tools.' >&2
  exit 1
fi

mkdir -p "$(dirname "$executable")"
xcrun clang \
  -target "${arch}-apple-macosx13.0" \
  -c "$root/Sources/ProcessSamplingBridge.c" \
  -o "$root/build/ProcessSamplingBridge.o"
xcrun clang \
  -target "${arch}-apple-macosx13.0" \
  -fobjc-arc \
  -fblocks \
  -c "$root/Sources/NetworkStatisticsBridge.m" \
  -o "$root/build/NetworkStatisticsBridge.o"
xcrun swiftc \
  -target "${arch}-apple-macosx13.0" \
  -import-objc-header "$root/Sources/TouchBarPrivate.h" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Foundation \
  -framework ServiceManagement \
  -framework IOKit \
  -F /System/Library/PrivateFrameworks \
  -framework DFRFoundation \
  -o "$executable" \
  "$root"/Sources/*.swift \
  "$root/build/ProcessSamplingBridge.o" \
  "$root/build/NetworkStatisticsBridge.o"

cp "$root/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
echo "App creada: $app"
