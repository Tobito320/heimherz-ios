#!/usr/bin/env bash
# Privat-Check: keine Signier-, Schlüssel- oder .cred-Dateien und keine Tresorschlüssel im Git (Arbeitsbaum, Historie, Commit-Texte).
# Ausgabe nennt nur Fundstellen (Commit:Pfad), nie den Treffertext. Exit 0 = sauber, 1 = Fund.
# Erlaubt sind nur die bekannten Test-Werte aus fixtures/ und den Tests (erfundene Daten, SPEC 19).
# PRIVAT_STRENG=1 wird von ci-fenster.sh gesetzt; hier ohne Wirkung (es gibt keine lokale Begriffsdatei), bleibt aus Kompatibilität.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fund=0

# Bekannte Test-Werte: Schlüssel 0x01..0x20 (Standard-b64 und b64url), Test-Token 0x40..0x5f (b64url)
BEKANNT='AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA|QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8'

signier=$(git log --all --name-only --format= | grep -E '\.(p12|p8|mobileprovision|key|pem|cer|csr|cred)$' | sort -u)
if [ -n "$signier" ]; then echo "FUND: Signier-, Schlüssel- oder .cred-Datei in der Historie:"; echo "$signier"; fund=1; fi

if git log --all -p | grep -q -E -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AuthKey_[A-Z0-9]{6,}'; then
  echo "FUND: Schlüsselmuster in der Historie"; fund=1
fi

# 32-Byte-Werte: Standard-b64 mit Füllzeichen (44 Zeichen) überall; ungefüllte b64url-Form (43 Zeichen) nur nach schluessel= oder token=,
# denn Foto-Kennungen (SHA-256, b64url) sehen genauso aus.
MUSTER_B64='(^|[^A-Za-z0-9+/])[A-Za-z0-9+/]{43}=([^A-Za-z0-9+/=]|$)'
MUSTER_URL='(schluessel|token)=[A-Za-z0-9_-]{43}([^A-Za-z0-9_-]|$)'
fremd() { grep -o -E -e "$MUSTER_B64" -e "$MUSTER_URL" | grep -v -E "$BEKANNT" | head -1; }

# Arbeitsbaum (tracked und untracked, ohne ignorierte Dateien)
if git grep -h -I --untracked -E -e "$MUSTER_B64" -e "$MUSTER_URL" -- . 2>/dev/null | fremd | grep -q .; then
  echo "FUND im Arbeitsbaum: 32-Byte-Wert, der nicht der Test-Schlüssel oder das Test-Token ist. Fundstellen:"
  git grep -l -I --untracked -E -e "$MUSTER_B64" -e "$MUSTER_URL" -- . 2>/dev/null
  fund=1
fi
# Historie
revs=$(git rev-list --all)
if [ -n "$revs" ]; then
  # shellcheck disable=SC2086
  if git grep -h -I -E -e "$MUSTER_B64" -e "$MUSTER_URL" $revs -- . 2>/dev/null | sed -E 's/^[0-9a-f]{40}://' | fremd | grep -q .; then
    echo "FUND in der Historie: 32-Byte-Wert, der nicht der Test-Schlüssel oder das Test-Token ist (Commit:Pfad):"
    # shellcheck disable=SC2086
    git grep -l -I -E -e "$MUSTER_B64" -e "$MUSTER_URL" $revs -- . 2>/dev/null | sed -E 's/^([0-9a-f]{7})[0-9a-f]*:/\1:/' | sort -u
    fund=1
  fi
fi

if [ "$fund" = "0" ]; then echo "sauber: keine Signierdatei, kein Schlüsselmuster, kein fremder 32-Byte-Wert"; fi
exit "$fund"
