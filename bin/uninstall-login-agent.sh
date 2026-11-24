#!/usr/bin/env bash
set -euo pipefail
label="dev.touchbarkitt.studio"
destination="$HOME/Library/LaunchAgents/$label.plist"
launchctl bootout "gui/$(id -u)" "$destination" 2>/dev/null || true
rm -f "$destination"
echo "Desinstalado: $label"
