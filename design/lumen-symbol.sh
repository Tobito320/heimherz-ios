#!/usr/bin/env bash
# Lumen-Familie: erzeugt die drei App-Symbole (normal, dunkel, getönt) 1024x1024 ohne Alpha aus einem Zeichen.
# Aufruf: bash design/lumen-symbol.sh design/glyphen/cloud.svg ZIELORDNER   (Zeichen: cloud, connect, wallet; eigene Zeichen ebenso, Füllung fill="url(#k)")
# Ergebnis: ZIELORDNER/icon-1024.png, icon-1024-dark.png, icon-1024-tinted.png. Braucht rsvg-convert, magick, python3.
set -eu
glyph=$(cat "${1:?Zeichen-SVG}"); ziel="${2:?Zielordner}"; vorlage="$(dirname "$0")/lumen-symbol.svg.vorlage"
mkdir -p "$ziel"; tmp=$(mktemp -d)
baue() { # Name BG A B C Schein Deckkraft
  python3 - "$vorlage" "$glyph" "$2" "$3" "$4" "$5" "$6" "$7" > "$tmp/$1.svg" <<'PY'
import sys
v=open(sys.argv[1]).read()
for k,x in zip(['@GLYPH@','@BG@','@A@','@B@','@C@','@S@','@SO@'],sys.argv[2:9]): v=v.replace(k,x)
print(v)
PY
  rsvg-convert -w 1024 -h 1024 "$tmp/$1.svg" -o "$tmp/$1.png"
  magick "$tmp/$1.png" -background "$2" -alpha remove -alpha off "$ziel/$1.png"
}
baue icon-1024 '#07070A' '#FFFFFF' '#FFE98F' '#FF9A1F' '#FFB020' 0.55
baue icon-1024-dark '#07070A' '#FFFFFF' '#FFE98F' '#FF9A1F' '#FFB020' 0.55
baue icon-1024-tinted '#000000' '#FFFFFF' '#D8D8D8' '#9A9A9A' '#FFFFFF' 0.0
