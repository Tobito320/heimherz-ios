# Heimherz – Regeln für Agenten

Eigene Brücke PC ↔ iPhone für Passwörter (AutoFill), Fotos und Dateien. Nur für Ahmed. Spec: `SPEC.md` (Wahrheit, Module Abschnitt 3), Begriffe `CONTEXT.md`, Latte `CONSTRAINTS.md`, Plan `tasks/plan.md`, Aufgaben `tasks/todo.md`. Vorlage für Projekt, CI, Signieren und Design: `~/projects/bahnherz-ios` (dort `CLAUDE.md` Abschnitt Code mit den Swift-6-Fallen lesen).

## Pfade
- Repo `/home/tobi/projects/heimherz-ios` (Link `~/code/heimherz-ios`), GitHub `Tobito320/heimherz-ios`, privat.
- PC-Teil: `lib/` (Tresor-Format TS), `server/` (Dienst), `bin/heimherz` (CLI), Tests mit `~/.bun/bin/bun test`.
- iOS-Teil: `project.yml`, `Gemeinsam/`, `Heimherz/`, `HeimherzAutoFill/`, `HeimherzFotos/`, `HeimherzTeilen/`. Gemeinsame Fixtures `fixtures/` lesen Bun und XCTest.
- Jede Datei gehört einem Modul (SPEC 3). Fremde Modulordner nie ändern; Wünsche in den Abschlussbericht.

## Sicherheit (zuerst)
- Passwörter, Tresorschlüssel, Geräte-Token nie in stdout, Logs, Dateien, Commits, Tests oder in den Kontext eines Agenten. Tests nur mit erfundenen Daten und dem Test-Schlüssel aus `fixtures/tresor/umschlag-1.json`.
- Der Server sieht nie Klartext. Schlüssel am PC nur über `systemd-creds --user`, am Handy nur im Schlüsselbund.
- Nur CryptoKit und WebCrypto, keine eigene Krypto. Dienst nur `127.0.0.1`, nach außen nur `tailscale serve`, nie Funnel oder Cloudflare.
- Fotos am Handy nie löschen oder ändern. Dateien am PC nur in den Papierkorb (`trash-put`).

## Bau
- Kein Mac, kein Swift lokal. iOS wird nur in GitHub Actions gebaut (`ios-ci.yml`, `macos-26`). Lokal: `swift-syntax-check <Dateien>` (falls da), `bash scripts/check-schnell.sh`.
- Actions laufen nur bei öffentlichem Repo: `bash scripts/pruefe-privat.sh`, dann `scripts/ci-fenster.sh` im Hintergrund. Nie GitHub-Billing vorschlagen.
- TestFlight nur von Hand: `gh workflow run testflight.yml --repo Tobito320/heimherz-ios --ref main`.

## Code
- Wie Bahnherz: Swift 6 strikt, Bezeichner ASCII Deutsch, Oberflächentexte Deutsch mit Umlauten, keine Emojis, keine Swift-Pakete, keine npm-Pakete. Test zuerst. Ponytail: kleinster korrekter Diff.
- Gespeicherte Typen: neue Felder optional; unbekannte Tresor-Felder bleiben erhalten (SPEC 5).
- Commit-Nachrichten kurz auf Deutsch, am Ende die vom System vorgegebenen Zeilen `Co-Authored-By` und `Claude-Session`.
- Ehrlich berichten: was nur Compiler oder Gerät beweist, ist "ungeprüft", bis CI grün ist oder Ahmed es am Handy sieht.
