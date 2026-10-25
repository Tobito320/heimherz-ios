# Qualitätslatte

Nie absenken, damit etwas durchgeht.

- `bun test` grün, keine übersprungenen Tests, keine gelöschten Asserts.
- iOS: CI grün mit Swift 6 strikt; keine `@preconcurrency`- oder `nonisolated(unsafe)`-Abkürzung ohne Kommentar `shortcut:` mit Grund.
- Jede Server-Route hat einen Test für fehlendes Token (401). Jeder Pfad-Eingang hat einen Ausbruch-Test.
- Krypto und Merge: TS und Swift lesen dieselben Dateien in `fixtures/`; ein Fixture ändern heißt beide Seiten prüfen.
- Kein Geheimnis in Ausgabe, Log, Commit (Privat-Check `scripts/pruefe-privat.sh`).
- Barrierefreiheit: jede Taste mit Beschriftung für VoiceOver, Dynamic Type bis XXL ohne abgeschnittene Texte.
