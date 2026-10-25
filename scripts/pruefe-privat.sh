#!/usr/bin/env bash
# Privat-Check: keine Orte-Werte, Signierdateien oder Schlüssel im Git (Arbeitsbaum, Historie, Commit-Texte).
# Die Suchbegriffe entstehen zur Laufzeit aus der lokalen, gitignorierten BekannteOrte.json; nichts davon steht in dieser Datei.
# Ausgabe nennt nur Fundstellen (Commit:Pfad), nie den Treffertext. Exit 0 = sauber, 1 = Fund, 2 = Begriffe fehlen im Streng-Modus.
# PRIVAT_STRENG=1 verlangt die lokale Datei (vor jedem öffentlichen CI-Fenster).
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
DATEI="Bahnherz/Resources/BekannteOrte.json"
fund=0

if git ls-files --error-unmatch "$DATEI" >/dev/null 2>&1 || [ -n "$(git log --all --diff-filter=A --name-only --format= -- "$DATEI")" ]; then
  echo "FUND: $DATEI steht oder stand im Git"; fund=1
fi

signier=$(git log --all --name-only --format= | grep -E '\.(p12|p8|mobileprovision|key|pem|cer|csr)$' | sort -u)
if [ -n "$signier" ]; then echo "FUND: Signierdatei in der Historie:"; echo "$signier"; fund=1; fi

if git log --all -p | grep -q -E -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AuthKey_[A-Z0-9]{6,}'; then
  echo "FUND: Schlüsselmuster in der Historie"; fund=1
fi

if [ ! -f "$DATEI" ]; then
  if [ "${PRIVAT_STRENG:-0}" = "1" ]; then echo "FEHLT: $DATEI (Streng-Modus)"; exit 2; fi
  echo "Hinweis: keine lokale $DATEI, Orte-Suche übersprungen"
  exit "$fund"
fi

L=$(mktemp); H=$(mktemp); trap 'rm -f "$L" "$H"' EXIT
{
  # Jedes Adress-/Namenstück zwischen Kommas (ab 6 Zeichen) und der Straßenstamm ohne Hausnummer
  jq -r '.personen[].orte[].adresse' "$DATEI" | tr ',;' '\n\n' | sed -E 's/^ +//; s/ +$//'
  jq -r '.personen[].orte[].adresse' "$DATEI" | tr ',;' '\n\n' | sed -E 's/^ +//; s/ +$//; s/ +[0-9]+[a-z]?(-[0-9]+)?$//'
  # Postleitzahl mit Ort ist öffentlich (steht auch in den Fahrplan-Fixtures) und wird nicht gesucht.
  # Koordinaten auf vier Nachkommastellen (abgeschnitten) als Zeichenkette
  jq -r '.personen[].orte[] | [.breite, .laenge] | .[] | tostring' "$DATEI" | sed -E 's/^([0-9]+\.[0-9]{4}).*/\1/'
} | awk 'length >= 6 && $0 !~ /^[0-9][0-9][0-9][0-9][0-9] [^0-9]*$/' | sort -u > "$L"

if [ ! -s "$L" ]; then echo "FEHLT: keine Suchbegriffe aus $DATEI"; exit 2; fi

# Arbeitsbaum (tracked und untracked, ohne ignorierte Dateien) und alle Commits
treffer=$(git grep -l -i -F -f "$L" --untracked -- . ":!$DATEI" 2>/dev/null)
if [ -n "$treffer" ]; then echo "FUND im Arbeitsbaum:"; echo "$treffer"; fund=1; fi
revs=$(git rev-list --all)
if [ -n "$revs" ]; then
  # shellcheck disable=SC2086
  treffer=$(git grep -l -i -F -f "$L" $revs -- . ":!$DATEI" 2>/dev/null | sed -E 's/^([0-9a-f]{7})[0-9a-f]*:/\1:/')
  if [ -n "$treffer" ]; then echo "FUND in der Historie (Commit:Pfad):"; echo "$treffer" | sort -u; fund=1; fi
  if git log --all --format='%an%n%ae%n%B' | grep -q -i -F -f "$L"; then echo "FUND in Commit-Texten oder Autor"; fund=1; fi
fi

# Haltestellen-IDs der Orte: öffentliche Fahrplandaten, aber die ID des Zuhauses grenzt den Wohnort auf Ortsteil-Ebene ein.
# Im Arbeitsbaum ein Fund (Fixtures, Tests und CI-Links nehmen andere Haltestellen); in der Historie nur ein Hinweis,
# denn die Historie wird nicht umgeschrieben.
jq -r '.personen[].orte[] | .haltestelle // empty' "$DATEI" | sort -u > "$H"
if [ -s "$H" ]; then
  treffer=$(git grep -l -F -f "$H" --untracked -- . ":!$DATEI" 2>/dev/null)
  if [ -n "$treffer" ]; then echo "FUND: Haltestellen-ID eines Ortes im Arbeitsbaum:"; echo "$treffer"; fund=1; fi
  if [ -n "$revs" ]; then
    # shellcheck disable=SC2086
    alt=$(git grep -l -F -f "$H" $revs -- . ":!$DATEI" 2>/dev/null | sed -E 's/^[0-9a-f]+://' | sort -u)
    if [ -n "$alt" ]; then echo "Hinweis: Haltestellen-ID eines Ortes steht in der Historie (kein Fund, wird nicht umgeschrieben):"; echo "$alt"; fi
  fi
fi

if [ "$fund" = "0" ]; then echo "sauber: $(wc -l < "$L" | tr -d ' ') Suchbegriffe, keine Fundstelle"; fi
exit "$fund"
