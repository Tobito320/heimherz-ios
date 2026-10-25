# Todo: Heimherz

- [ ] T1 tresor-format: lib/umschlag.ts, lib/zusammenfuehren.ts, lib/totp.ts, fixtures/ (umschlag, merge, totp), Tests. Verify: `bun test lib`
- [ ] T2 pc-dienst: server/ alle Routen SPEC 6 mit Tests (Auth, 409, Verlauf, Fotos, Pfade, Papierkorb). Verify: `bun test server`
- [ ] T3 pc-werkzeug: bin/heimherz (einrichten, koppeln, import/export bitwarden, liste, status, geraet weg). Verify: `bun test bin`, Ende-zu-Ende gegen Testdienst
- [x] T4 ios-grundgeruest: project.yml, CI, Gemeinsam (Krypto, Merge, TOTP, Schlüsselbund, Ablage, Client, Koppeln), Tabs, Design. Verify: CI grün, XCTest liest TS-Fixtures
- [ ] T5 ios-passwoerter. Verify: CI grün
- [ ] T6 ios-fotos (App-Abgleich + Erweiterung). Verify: CI grün
- [ ] T7 ios-dateien. Verify: CI grün
- [ ] T8 ios-autofill. Verify: CI grün
- [ ] T9 freigabe: Dienst, Tailscale HTTPS, Portal, Profile, TestFlight, Lovea-Notiz. Verify: Build in TestFlight, `curl` über Tailnet mit Token = 200, ohne = 401
