#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/Tests/PulseModelsTests.swift" "$tmp/main.swift"
swiftc "$root/Sources/SignalThreshold.swift" "$root/Sources/PulseModels.swift" "$root/Sources/AppLanguage.swift" "$root/Sources/ProcessFamily.swift" "$root/Sources/NetworkModels.swift" "$root/Sources/AnimationMath.swift" "$root/Sources/MarqueeText.swift" "$tmp/main.swift" -o "$tmp/pulse-tests"
"$tmp/pulse-tests"
