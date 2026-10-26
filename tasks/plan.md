# Plan: Heimherz

Quelle: `SPEC.md`. Module und Reihenfolge: SPEC Abschnitt 3.

## Phasen
1. `tresor-format` (lib/, fixtures/): Vertrag zwischen PC und Handy. Erst wenn `bun test` grün ist, startet alles andere.
2. Parallel, je eigener Worktree:
   - A `pc-dienst` + `pc-werkzeug` (server/, bin/): lokal voll testbar mit `bun test`.
   - B `ios-grundgeruest` (project.yml, Gemeinsam/, Heimherz/Sources/App + Design + Module/Mehr, CI): CI grün im Fenster.
3. Parallel nach B: `ios-passwoerter`, `ios-fotos`, `ios-dateien` (je nur eigener Modulordner plus Tests).
4. `ios-autofill` (HeimherzAutoFill/), braucht Passwörter-Modul.
5. `freigabe`: Dienst am PC an, Tailscale HTTPS, Apple-Portal, TestFlight, Lovea-Notiz für Ahmed.

## Risiken
- Swift nur in CI prüfbar: kleine Schritte, Swift-Fixtures dieselben wie TS.
- Foto-Erweiterung wacklig (iOS 26.2): App-Abgleich ist der Hauptweg.
- Portal-Login (App Group, App-Eintrag) braucht Ahmed einmal.
- HTTPS im Tailnet aus: Admin-Konsole nötig.

## Prüfpunkte
- Nach 1: `bun test` grün, Fixtures stehen.
- Nach 2A: Ende-zu-Ende lokal (Dienst + CLI + Umschlag-Fixture).
- Nach 2B und 3/4: CI grün.
- Nach 5: TestFlight-Build, Ahmed testet die Erfolgskriterien SPEC 20.

## T12 agenten-fuellen (SPEC 23)
1. `bin/stufen.ts` + Test (reine Logik, zuerst).
2. `bin/totp.ts` + Test gegen RFC-Fixture.
3. `bin/fuellen.ts`: Eintragswahl + Test; CDP-Teil gegen Wegwerf-Chrome (Port 9556, Testseite per `data:`/lokalem http geht nicht, da https Pflicht: Prüfschalter nur in Tests).
4. CLI verdrahten, `claude-bw` Wächter, echte Prüfung, Doku (Übersicht, Skill `claude-bw`, Wunschliste W-006 Stand).

## T16 passkeys (W-025, SPEC 24)
1. SPEC 24, Plan, Todo. Prüfung: Abschnitt steht.
2. `Gemeinsam/AutoFill/Passkeys.swift`: Lesen (beide Formate), authenticatorData, Signatur, Anlegen mit CBOR, Ablage im Tresor; Tests mit festen Vektoren zuerst. Prüfung: Syntax lokal, CI.
3. Identitäten (`AutoFillIdentitaeten`) + Test. Prüfung: CI.
4. Modell (`AutoFillModell`: Aufträge `.passkey`, `.passkeyNeu`, Phase `.passkeyWahl`) + Tests mit Attrappen. Prüfung: CI.
5. Erweiterung (Controller, Ansicht Auswahl, Info.plist `ProvidesPasskeys`). Prüfung: CI grün inkl. Release-Bau.
6. Merge nach main, TestFlight, Wunschliste/Übersicht, Bericht. Prüfung: Build in TestFlight; Gerät = Ahmed.

## T21 dateien-durchsuchen (Ahmed 26.10.2026, Stand-Datei `~/.claude/buero-stand/heimcloud-dateien2-26-10.md`)
Ziel: Startseite des Tabs wie "Durchsuchen" in Apple Dateien (ohne Tags/Favoriten), drei Abschnitte Bürokratie, Projekte, Weitere; Ordnersymbol wie Apple (selbst gezeichnet, nicht schwarz im Schlitz).
1. Logik zuerst, Tests zuerst (`Tests/Dateien/DateienStartTests.swift`): Abschnitte bilden (feste Reihenfolge, fehlende Kategorie fehlt, Weitere sammelt Fremde, volle Pfade), Symbol-Tabelle (echte Ordnernamen), Sortierung (`_` zuletzt), Einklapp-Zustand (RawRepresentable). Prüfung: `swift-syntax-check`.
2. `DateienStart.swift`: Typen, Logik, `DateienStartModell` (Wurzel + drei Kategorien parallel, Fehler behalten alte Daten). Prüfung: Tests.
3. `OrdnerSymbol` (SwiftUI-Shapes) in `DateienAnsichten.swift`, in `DateiBild` und Informationen statt `folder.fill`. Prüfung: Screenshots hell/dunkel.
4. Startseite im Wurzel-`OrdnerSeite` (groß betitelt, inset grouped, Kopfzeile mit Pfeil, AppStorage). Prüfung: Screenshots.
5. Demo-Daten und Debug-Schalter auf die neue Ordnung, CI-Screenshots (Start hell/dunkel/XXL, Ordnerraster, Liste). Prüfung: CI grün, Screenshots gegen Vorbilder.
6. SPEC 12, todo T21. Prüfung: `bun test`, `check-schnell.sh`.
Grenzen: kein Merge nach main, kein TestFlight, keine neue Server-Route, `Gemeinsam/` unberührt.
## T23 sicherung (W-035 bis W-037, SPEC 25)
1. SPEC 25, Plan, Todo.
2. `lib/sicherung.ts` (Format, Aufbewahrung, Wiederherstellungsblatt) + Test mit Testvektor `fixtures/sicherung/wiederherstellung-1.json`.
3. Dienst: `GET/PUT /v1/wiederherstellung` + Test.
4. CLI `heimherz sicherung` (+ rclone) und `heimherz wiederherstellen` + Tests; Units `server/heimherz-sicherung.*`.
5. iOS W-037 `PasswortGesundheit` + Ansicht + XCTest.
6. iOS W-036 `Wiederherstellung.swift` + Einstellungen (Code, Sicherung-Stand) + `HeimClient` + XCTest.
7. `check-schnell.sh`, Push, PR (nicht mergen).
