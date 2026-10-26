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
