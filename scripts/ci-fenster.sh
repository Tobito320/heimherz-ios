#!/usr/bin/env bash
# CI-Fenster: Historien-Check, Repo kurz öffentlich, Push, ios-ci abwarten, Repo sofort wieder privat.
# GitHub rechnet private Actions nicht ab; Läufe starten nur bei öffentlichem Repo. Nie GitHub-Billing vorschlagen.
# Aufruf (im Hintergrund, nie im Vordergrund warten): bash scripts/ci-fenster.sh [--tag NAME]
# Das Repo wird auch bei Abbruch oder Fehler wieder privat (trap).
set -u
REPO="Tobito320/heimherz-ios"
cd "$(git rev-parse --show-toplevel)" || exit 2
tag=""
[ "${1:-}" = "--tag" ] && tag="${2:-}"

PRIVAT_STRENG=1 bash scripts/pruefe-privat.sh || { echo "Privat-Check nicht sauber, Abbruch (Repo bleibt privat)"; exit 3; }

zurueck() {
  gh repo edit "$REPO" --visibility private --accept-visibility-change-consequences >/dev/null 2>&1
  echo "Sichtbarkeit jetzt: $(gh repo view "$REPO" --json visibility -q .visibility 2>/dev/null)"
}
trap zurueck EXIT

gh repo edit "$REPO" --visibility public --accept-visibility-change-consequences >/dev/null || { echo "Öffentlich schalten fehlgeschlagen"; exit 4; }
echo "Sichtbarkeit: $(gh repo view "$REPO" --json visibility -q .visibility)"

# Direkt nach dem Öffentlich-Schalten antwortet GitHub beim Push manchmal kurz mit 403: bis zu fünfmal wiederholen.
for versuch in 1 2 3 4 5; do
  if git push origin main >/dev/null 2>&1; then echo "Push ok (Versuch $versuch)"; break; fi
  echo "Push Versuch $versuch fehlgeschlagen"
  sleep 15
done
sha=$(git rev-parse HEAD)
id=""
# Kurz auf den vom Push ausgelösten Lauf warten (höchstens vier Minuten)
for _ in $(seq 1 24); do
  id=$(gh run list --repo "$REPO" --workflow ios-ci.yml --commit "$sha" --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  [ -n "$id" ] && break
  sleep 10
done
[ -z "$id" ] && { echo "Kein CI-Lauf für $sha gefunden"; exit 5; }
echo "Lauf: https://github.com/$REPO/actions/runs/$id"
if gh run watch "$id" --repo "$REPO" --exit-status --interval 30 >/dev/null 2>&1; then
  echo "ERGEBNIS: grün ($id)"
  if [ -n "$tag" ]; then git tag -f "$tag" "$sha" && git push -f origin "$tag" 2>&1 | tail -1; fi
  rc=0
else
  echo "ERGEBNIS: rot ($id)"
  rc=1
fi
gh run view "$id" --repo "$REPO" --json jobs -q '.jobs[] | "\(.name): \(.conclusion)"'
exit "$rc"
