# Todo: Heimherz

- [x] T1 tresor-format: lib/umschlag.ts, lib/zusammenfuehren.ts, fixtures/ (umschlag, merge, totp), Tests. Verify: `bun test lib`
- [x] T2 pc-dienst: server/ alle Routen SPEC 6 mit Tests (Auth, 409, Verlauf, Fotos, Pfade, Papierkorb). Verify: `bun test server`
- [x] T3 pc-werkzeug: bin/heimherz (einrichten, koppeln, import/export bitwarden, liste, status, geraet weg). Verify: `bun test bin`, Ende-zu-Ende gegen Testdienst
- [x] T4 ios-grundgeruest: project.yml, CI, Gemeinsam (Krypto, Merge, TOTP, Schlüsselbund, Ablage, Client, Koppeln), Tabs, Design. Verify: CI grün, XCTest liest TS-Fixtures
- [x] T5 ios-passwoerter. Verify: CI grün (Lauf 40152224883, 142 Tests)
- [x] T6 ios-fotos (App-Abgleich + Erweiterung, Server: OPTIONS für Upload-Jobs). Verify: CI grün, bun test
- [x] T7 ios-dateien. Verify: CI grün
- [x] T8 ios-autofill. Verify: CI grün (Lauf 40152224883, 142 Tests, Release-Bau mit Erweiterung)
- [ ] T9 freigabe: Dienst, Tailscale HTTPS, Portal, Profile, TestFlight, Lovea-Notiz. Verify: Build in TestFlight, `curl` über Tailnet mit Token = 200, ohne = 401 — Stand 25.10.: Dienst, Tailscale HTTPS, Portal, Profile, Build 1 in TestFlight erledigt; offen nur Ahmeds Test am Gerät (SPEC 20)
- [x] T10 passwoerter-wie-apple (W-001, W-002, W-004): Kacheln, Listen A bis Z, Codes, Passkeys, Sicherheit, Gelöscht (Grabstein behält Felder), Symbole (`GET /v1/symbol`), Import aus Apple Passwörter (Credential Exchange). Verify: `bun test`, CI grün, Screenshots; offen nur am Gerät (Symbole echter Seiten, Face ID, Exportliste von iOS)
- [x] T11 fotos-runde2 (W-003): Start/Anhalten in Stücken, Raster mit Status, Hintergrund (BGContinuedProcessingTask, Nachtlauf, handleEventsForBackgroundURLSession). Verify: CI grün, Screenshots; offen nur am Gerät (Hintergrund, 8000+ Bilder, iCloud-Originale)
- [x] T12 umbenennen (W-005): sichtbarer Name "Heim", ASC-Name "Heim Tresor"; Import-Annahme in `AppRootView` (springt auf Passwörter)
- [ ] T15 passwoerter-runde3 (W-012, W-014 bis W-017, W-020, W-021): Codes antippen und nächster Code, Passwort ändern, Datenlecks (Pwned Passwords, k-Anonymität), frühere Passwörter, Zuletzt benutzt, doppelte Konten, Spotlight. Verify: CI grün, Screenshots; offen nur am Gerät (Safari-Adresse, Face ID, echter HIBP-Aufruf, Spotlight-Tipp)
