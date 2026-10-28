#!/usr/bin/env bash
# Packt browser/ zu lumen.crx und liefert es lokal aus (Dienst lumen-erweiterung, Policy ExtensionInstallForcelist). Vorher "version" in manifest.json erhöhen.
set -euo pipefail
hier=$(cd "$(dirname "$0")" && pwd); d="$HOME/.local/share/lumen-erweiterung"; t=$(mktemp -d)
cp "$hier"/{manifest.json,hintergrund.js,inhalt.js,passkey.js} "$t/" 2>/dev/null; mkdir "$t/x" && mv "$t"/*.js "$t"/manifest.json "$t/x/"
/opt/google/chrome/chrome --headless=new --no-sandbox --user-data-dir="$t/p" --pack-extension="$t/x" --pack-extension-key="$d/schluessel.pem" >/dev/null 2>&1 || true
[ -s "$t/x.crx" ] || { echo "Packen fehlgeschlagen"; exit 1; }
v=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$hier/manifest.json")
mkdir -p "$d/web" && cp "$t/x.crx" "$d/web/lumen.crx"
cat > "$d/web/update.xml" <<X
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='mdjdbdlhjflakglpihdkaipkfnfeding'><updatecheck codebase='http://127.0.0.1:8797/lumen.crx' version='$v' /></app>
</gupdate>
X
rm -rf "$t"; echo "ok: Version $v ausgeliefert, Chrome holt sie beim nächsten Update-Lauf"
