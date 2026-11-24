#!/usr/bin/env bash
# Compile an AppKit harness against the same sources as the application.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_file="${1:?Harness source required}"
output="${2:?Output executable required}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
arch="$(uname -m)"
xcrun clang -target "${arch}-apple-macosx13.0" -c "$root/Sources/ProcessSamplingBridge.c" -o "$tmp/process.o"
xcrun clang -target "${arch}-apple-macosx13.0" -fobjc-arc -fblocks -c "$root/Sources/NetworkStatisticsBridge.m" -o "$tmp/network.o"
cp "$source_file" "$tmp/main.swift"
sources=()
for file in "$root"/Sources/*.swift; do
  [[ "$(basename "$file")" == "main.swift" ]] || sources+=("$file")
done
xcrun swiftc -target "${arch}-apple-macosx13.0" \
  -import-objc-header "$root/Sources/TouchBarPrivate.h" \
  -framework AppKit -framework SwiftUI -framework Foundation -framework ServiceManagement -framework IOKit \
  -F /System/Library/PrivateFrameworks -framework DFRFoundation \
  "${sources[@]}" "$tmp/main.swift" "$tmp/process.o" "$tmp/network.o" -o "$output"
