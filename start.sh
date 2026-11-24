#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/TouchBarKITT.app"
if [[ ! -x "$app/Contents/MacOS/TouchBarKITT" ]]; then
  "$root/build.sh"
fi
open "$app"
