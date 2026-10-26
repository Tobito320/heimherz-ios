#!/usr/bin/env bash
# Schnellcheck vor jedem Commit: Syntax geänderter Swift-Dateien, JSON, Shell, Workflows, Privat-Check, Bun-Tests.
# Mit --alle werden alle Swift-Dateien geprüft. Kein Compiler: fängt Tippfehler, keine Typen.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fehler=0

if [ "${1:-}" = "--alle" ]; then
  dateien=$(git ls-files --cached --others --exclude-standard -- '*.swift')
else
  dateien=$( { git diff --name-only --diff-filter=d HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift'; } | sort -u )
fi
if [ -n "$dateien" ]; then
  echo "$dateien" | tr '\n' '\0' | xargs -0 swift-syntax-check || fehler=1
else
  echo "Keine Swift-Dateien zu prüfen"
fi

while IFS= read -r j; do
  jq -e . "$j" >/dev/null || { echo "JSON kaputt: $j"; fehler=1; }
done < <(git ls-files --cached --others --exclude-standard -- '*.json')
for s in scripts/*.sh; do bash -n "$s" || { echo "Shell-Syntax: $s"; fehler=1; }; done
if command -v shellcheck >/dev/null 2>&1; then shellcheck -S warning scripts/*.sh || fehler=1; fi
# Workflows wie in ios-ci (actionlint plus shellcheck). Der lokale actionlint kennt das Label macos-26 noch nicht, der in CI schon.
if command -v actionlint >/dev/null 2>&1; then
  actionlint -ignore 'label "macos-26" is unknown' || fehler=1
fi
bash scripts/pruefe-privat.sh || fehler=1
# Lumen-Kit: nur Warnung (das Kit liegt im Vault, in GitHub-CI nicht erreichbar)
if command -v lumen-sync >/dev/null 2>&1; then lumen-sync --pruefe . || echo "WARNUNG: Lumen-Kit nicht aktuell (siehe oben), kein Fehler"; fi
# Tresor-Format (TS): dieselben Fixtures wie die Swift-Tests
BUN="${BUN:-$HOME/.bun/bin/bun}"
if [ -x "$BUN" ]; then "$BUN" test lib || fehler=1; else echo "Hinweis: bun fehlt, lib-Tests übersprungen"; fi
exit "$fehler"
