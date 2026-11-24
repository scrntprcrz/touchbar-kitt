#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$root/bin/build-harness.sh" "$root/Tests/RenderingTests.swift" "$tmp/rendering-tests"
"$tmp/rendering-tests"
