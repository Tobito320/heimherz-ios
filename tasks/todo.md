# Todo: Heimherz

- [x] T1 tresor-format: lib/umschlag.ts, lib/zusammenfuehren.ts, fixtures/ (umschlag, merge, totp), Tests. Verify: `bun test lib`
- [x] T2 pc-dienst: server/ alle Routen SPEC 6 mit Tests (Auth, 409, Verlauf, Fotos, Pfade, Papierkorb). Verify: `bun test server`
- [x] T3 pc-werkzeug: bin/heimherz (einrichten, koppeln, import/export bitwarden, liste, status, geraet weg). Verify: `bun test bin`, Ende-zu-Ende gegen Testdienst
- [x] T4 ios-grundgeruest: project.yml, CI, Gemeinsam (Krypto, Merge, TOTP, Schlüsselbund, Ablage, Client, Koppeln), Tabs, Design. Verify: CI grün, XCTest liest TS-Fixtures
- [x] T5 ios-passwoerter. Verify: CI grün (Lauf 40152224883, 142 Tests)
- [ ] T6 ios-fotos (App-Abgleich + Erweiterung, Server: OPTIONS für Upload-Jobs). Verify: CI grün, bun test
- [ ] T7 ios-dateien. Verify: CI grün
- [x] T8 ios-autofill. Verify: CI grün (Lauf 40152224883, 142 Tests, Release-Bau mit Erweiterung)
- [ ] T9 freigabe: Dienst, Tailscale HTTPS, Portal, Profile, TestFlight, Lovea-Notiz. Verify: Build in TestFlight, `curl` über Tailnet mit Token = 200, ohne = 401
