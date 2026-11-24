#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$root/bin/build-harness.sh" "$root/Tests/CaptureScreenshots.swift" "$tmp/capture-screenshots"
"$tmp/capture-screenshots" "${1:-$root/docs/screenshots}"
