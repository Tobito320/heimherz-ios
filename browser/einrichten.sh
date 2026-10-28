#!/usr/bin/env bash
# Meldet den Host bei Ahmeds Chrome an (nur Standardprofil ~/.config/google-chrome). Danach in Chrome einmal diesen Ordner als entpackte Erweiterung laden.
set -euo pipefail
hier=$(cd "$(dirname "$0")" && pwd)
ziel="$HOME/.config/google-chrome/NativeMessagingHosts"
mkdir -p "$ziel"
cat > "$ziel/com.lumen.cloud.json" <<J
{ "name": "com.lumen.cloud", "description": "Lumen Cloud", "path": "$hier/host", "type": "stdio",
  "allowed_origins": ["chrome-extension://mdjdbdlhjflakglpihdkaipkfnfeding/"] }
J
echo "ok: $ziel/com.lumen.cloud.json -> $hier/host"
