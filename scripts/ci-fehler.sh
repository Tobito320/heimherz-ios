#!/usr/bin/env bash
# Holt das Log des Jobs test-iphone eines CI-Laufs und zeigt nur Fehler, fehlgeschlagene Tests und Compiler-Warnungen.
# Aufruf: bash scripts/ci-fehler.sh [RUN-ID]    (ohne ID: der letzte Lauf von ios-ci.yml)
# Das Log landet in ~/.cache/heimherz-ci/<run>.log (nicht in /tmp: dort ist der Platz knapp).
set -u
REPO="Tobito320/heimherz-ios"
run="${1:-$(gh run list --repo "$REPO" --workflow ios-ci.yml --limit 1 --json databaseId -q '.[0].databaseId')}"
ordner="${XDG_CACHE_HOME:-$HOME/.cache}/heimherz-ci"
mkdir -p "$ordner"
ziel="$ordner/$run.log"

job=$(gh api "repos/$REPO/actions/runs/$run/jobs" -q '.jobs[] | select(.name=="test-iphone") | .id')
[ -n "$job" ] || { echo "Kein Job test-iphone in Lauf $run"; exit 2; }
if ! gh api "repos/$REPO/actions/jobs/$job/logs" --allow-escape-sequences 2>/dev/null \
    | sed -E 's/\x1b\[[0-9;]*m//g; s#/Users/runner/work/heimherz-ios/heimherz-ios/##' > "$ziel"; then
  echo "Log noch nicht verfügbar (Lauf läuft noch?)"; exit 3
fi
echo "Log: $ziel ($(wc -l < "$ziel" | tr -d ' ') Zeilen)"

echo "== Fehler"
grep -E ': error:|\*\* (BUILD|TEST) FAILED|Test Case .* failed' "$ziel" | sed -E 's/^[0-9T:.Z-]+ //' | sort -u | head -80
echo "== Warnungen (ohne Werkzeug-Meldungen)"
grep -E 'warning:' "$ziel" | grep -v -E 'appintentsmetadataprocessor|DeprecationWarning|COUNT=|grep "warning' \
  | sed -E 's/^[0-9T:.Z-]+ //' | sort -u | head -40
echo "== Testergebnis"
grep -E 'Executed [0-9]+ tests' "$ziel" | tail -2 | sed -E 's/^[0-9T:.Z-]+ //'
