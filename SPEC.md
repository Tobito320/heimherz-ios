# SPEC: Heimherz

Eigene Brücke zwischen Ahmeds PC und seinem iPhone für Passwörter, Fotos und Dateien. Ersetzt Bitwarden und iCloud (Passwörter, Fotos) am Handy. Stand 25.10.2026. Idee und Recherche: Vault `01 Inbox/Idee – Eigene Cloud (Passwörter, Fotos, Dateien).md`, `01 Inbox/Eigene Cloud – Recherche 25.10.2026.md`.

## 0. Ahmeds Auftrag (wörtlich)

> "Ich hatte vor, dass wir Fotos auf dem PC lassen und Passwörter und so, lokal, und dann mit einer iOS-App das auf mein Handy synchronisieren. Oder muss man eine Firma haben oder so, damit Apple sowas erlaubt wie Passwörter, so dass wir alles machen können, was Bitwarden schon kann. Und das sicher. Geht das zuverlässig 100%? Ich brauche nicht, dass ich Passwörter auf meinem PC synchron halte, sondern eine App, die als Brücke steht, sozusagen, die die Passwörter von meinem PC zu meinem Handy holen und dann von meinem Handy kann ich einfach nutzen. Da brauche ich iCloud-Passwörter nicht mehr. Oder ich kann von iCloud-Passwörter importieren alles von meiner App zu iCloud-Passwörter und somit halt es synchron halten, aber sowieso benutze ich nur noch von meiner App. Also kann ich Bitwarden zuverlässig ersetzen mit einer eigenen App und genauso für Fotos, dass ich Fotos erst von meinem Handy synchron auf meine App habe und dann brauche ich iCloud gar nicht mehr."

Danach: "Bauen" (25.10.2026, 01:40).

## 1. Ziel

- Am iPhone füllt Heimherz Passwörter und Einmalcodes in Safari und Apps aus (System-AutoFill, wie Bitwarden), auch offline und wenn der PC aus ist.
- Der Tresor liegt auf dem PC, das Handy hat eine verschlüsselte Kopie. Neue oder geänderte Passwörter am Handy landen auf dem PC.
- Fotos und Videos gehen vom iPhone auf den PC (Originale, Live Photos komplett). Das Handy behält alles, nichts wird am Handy gelöscht.
- Dateien auf dem PC (Ordner `~/Heimherz/Dateien`) sind am Handy ansehbar, teilbar, hochladbar.
- Nur im eigenen Tailnet erreichbar. Kein Konto bei Dritten, keine Firma, kein Abo.

Nutzer: nur Ahmed (ein iPhone, ein PC). Annika nicht.

### User Stories
1. Ich öffne eine Login-Seite in Safari, tippe ins Feld, über der Tastatur steht mein Konto aus Heimherz, Face ID, fertig.
2. Ich lege bei einer neuen Seite ein Konto an, iOS fragt "In Heimherz sichern?", ich tippe Ja, am nächsten Tag ist es auch am PC.
3. Die Seite will einen 2FA-Code: Heimherz füllt ihn aus (TOTP).
4. Ich mache Fotos, abends im WLAN liegen sie am PC unter `~/Heimherz/Fotos/2026/10/`.
5. Ich suche eine PDF vom PC, öffne sie am Handy, teile sie per WhatsApp.
6. Der PC ist aus: Passwörter gehen trotzdem, Fotos warten und gehen später.
7. Heimherz fällt aus (Build abgelaufen, Fehler): `heimherz export bitwarden` am PC gibt eine Datei, die Bitwarden einlesen kann.

## 2. Ehrliche Grenzen (bleiben so)

- Nicht 100 %: eigener Code ohne externe Prüfung. Darum: Bitwarden bleibt 4 Wochen parallel, Notausgang Export, Tresor-Verlauf am PC.
- TestFlight-Builds laufen nach 90 Tagen ab. Die App warnt ab Tag 75 (Build-Datum im Bundle).
- Hintergrund-Upload der Fotos entscheidet iOS. Die Foto-Erweiterung von iOS 26.1 ist laut Apple-Forum wacklig (26.2 löst teils nicht aus). Darum zwei Wege: Abgleich beim Öffnen der App plus Erweiterung.
- iCloud-Passwörter-Import per Credential Exchange: iOS listet Ziel-Apps nach eigenen Regeln, ob Heimherz erscheint, ist offen (unsicher).
- Passkeys: Phase 2, nicht im ersten Build (Abschnitt 14).
- PC aus = kein Abgleich. Tailscale weckt den PC nicht.

## 3. Capability Map

| Modul-ID | Aufgabe | Hängt ab von |
|---|---|---|
| `tresor-format` | Datenformat, Verschlüsselung, Zusammenführen, gemeinsame Test-Fixtures (TS und Swift) | – |
| `pc-dienst` | Bun-Server auf dem PC: Geräte-Token, Tresor-Ablage mit Verlauf, Foto-Empfang, Dateien | `tresor-format` (nur Umschlag, liest nie Inhalt) |
| `pc-werkzeug` | CLI `heimherz`: einrichten, koppeln (QR), Bitwarden-Import, Bitwarden-Export, liste, status | `tresor-format`, `pc-dienst` |
| `ios-grundgeruest` | Xcode-Projekt, CI, Design, Gemeinsam/ (Krypto, Merge, API, Schlüsselbund), Koppeln per QR | `tresor-format` |
| `ios-passwoerter` | Tresor-Ansicht, Suche, Bearbeiten, Generator, TOTP, Abgleich | `ios-grundgeruest`, `pc-dienst` |
| `ios-autofill` | Credential Provider Extension: Passwort, Einmalcode, Speichern (ab 26.2), Identitäten-Liste | `ios-passwoerter` |
| `ios-fotos` | Foto-Abgleich in der App und Hintergrund-Upload-Erweiterung | `ios-grundgeruest`, `pc-dienst` |
| `ios-dateien` | Datei-Browser, Vorschau, Teilen, Hochladen | `ios-grundgeruest`, `pc-dienst` |
| `freigabe` | Dienst am PC (systemd, tailscale serve HTTPS), Bundle IDs, Profile, TestFlight | alle |

Reihenfolge: `tresor-format` → `pc-dienst`, `ios-grundgeruest` (parallel) → `pc-werkzeug`, `ios-passwoerter`, `ios-fotos`, `ios-dateien` (parallel) → `ios-autofill` → `freigabe`.

## 4. Tech Stack

- PC: Bun 1.x (`~/.bun/bin/bun`), TypeScript, nur eingebaute Teile (`Bun.serve`, `bun:sqlite`, WebCrypto, `bun test`). Keine npm-Pakete.
- iOS: SwiftUI, Swift 6 strikt, iOS 26.1 als Mindestversion, iPhone. XcodeGen. Frameworks: CryptoKit, Security (Keychain), AuthenticationServices, Photos/PhotoKit, QuickLook, VisionKit (QR). Keine Swift-Pakete.
- Netz: Tailscale. Dienst lauscht nur `127.0.0.1:8790`, `tailscale serve --bg --https=443 http://127.0.0.1:8790` macht `https://tobi-1.<tailnet>.ts.net` nur im Tailnet erreichbar. HTTPS-Zertifikate sind im Tailnet noch aus (Aufgabe in `freigabe`).
- CI: wie Bahnherz (`macos-26`, `ios-ci.yml`, `testflight.yml`, `scripts/ci-fenster.sh`).

## 5. Modul `tresor-format`

### Daten
```json
{ "format": 1, "eintraege": [ {
  "id": "UUID", "art": "login|notiz",
  "name": "GitHub", "benutzer": "tobi", "passwort": "…", "urls": ["https://github.com"],
  "totp": "otpauth://totp/…" , "notiz": "", "favorit": false,
  "geaendert": "2026-10-25T01:40:00.000Z", "geloescht": false } ] }
```
Unbekannte Felder bleiben beim Lesen und Schreiben erhalten (Vorwärts-Verträglichkeit). Gelöschte Einträge bleiben als Grabstein (`geloescht: true`, Felder leer) 90 Tage.

### Verschlüsselung
- Tresorschlüssel K: 32 Zufallsbytes, einmal am PC erzeugt (`heimherz einrichten`).
- Umschlag: `{"v":1,"rev":N,"nonce":"b64(12)","daten":"b64(ciphertext||tag16)"}`, AES-256-GCM mit K, zusätzliche Daten (AAD) = `heimherz-tresor-v1`. `rev` steht nur außen, der Server vergibt sie.
- Swift: `AES.GCM.SealedBox(nonce:ciphertext:tag:)`; TS: WebCrypto `AES-GCM` (Ausgabe ist ciphertext||tag). Fixture `fixtures/tresor/umschlag-1.json` mit bekanntem Test-Schlüssel beweist, dass beide Seiten gleich lesen.

### Zusammenführen (gleich in TS und Swift)
Pro `id`: neueres `geaendert` gewinnt; Gleichstand: `geloescht` gewinnt, sonst lexikographisch größerer JSON-Text (deterministisch). Einträge nur auf einer Seite bleiben. Grabsteine älter als 90 Tage fallen raus. Fixtures `fixtures/merge/*.json` (`a`, `b`, `erwartet`), dieselben Dateien laufen in `bun test` und XCTest.

### TOTP
RFC 6238 (SHA1/SHA256/SHA512, 6 oder 8 Stellen, Periode 30 Standard), `otpauth://`-URI oder rohes Base32. Testvektoren aus RFC 6238 Anhang B als Fixture.

## 6. Modul `pc-dienst`

`server/` im Repo, Start `bun server/index.ts`. Datenordner per Umgebung `HEIMHERZ_DATEN` (Standard `~/.local/share/heimherz`), Fotos `HEIMHERZ_FOTOS` (Standard `~/Heimherz/Fotos`), Dateien `HEIMHERZ_DATEIEN` (Standard `~/Heimherz/Dateien`).

Auth: jedes Gerät hat ein Token (32 Byte, b64url). Der Server speichert nur SHA-256 davon in `geraete.json` (`{id, name, hash, angelegt, zuletzt}`). Header `Authorization: Bearer <token>`. Fehlt oder falsch: 401 ohne Hinweis. Vergleich zeitkonstant. Zusätzlich nur Anfragen von `127.0.0.1` (tailscale serve als Vorschalt).

| Methode und Pfad | Zweck |
|---|---|
| `GET /v1/status` | `{version, rev, fotos, belegt, frei}` |
| `GET /v1/tresor` | aktueller Umschlag (404 wenn leer) |
| `PUT /v1/tresor` mit `If-Match: <rev>` | neuer Umschlag; falsche rev = 409 mit aktuellem Umschlag; Größe bis 20 MB; prüft nur die Form des Umschlags; legt alte Fassung nach `tresor/verlauf/<rev>.json` (die letzten 200 bleiben) |
| `GET /v1/fotos/bekannt` | Liste der Kennungen schon empfangener Fotos `[{kennung, ressource, groesse}]` |
| `PUT /v1/fotos/<kennung>/<ressource>` | Rohdaten-Upload. Header `X-Aufnahme` (ISO-Datum), `X-Dateiname`. Streamt nach `.teil`, dann umbenennen nach `Fotos/JJJJ/MM/<datum>_<dateiname>`; gleiche Kennung und Größe schon da = 200 ohne Schreiben. Kennung nur `[A-Za-z0-9_-]{1,128}` |
| `GET /v1/dateien?pfad=` | Ordnerliste `[{name, ordner, groesse, geaendert}]` |
| `GET /v1/datei?pfad=` | Download mit Range |
| `PUT /v1/datei?pfad=` | Upload (überschreibt nie: bei Namensgleichheit ` (2)` anhängen) |
| `POST /v1/datei/papierkorb` `{pfad}` | in den Linux-Papierkorb (`trash-put`), nie löschen |

Uploads: bei Dateien ist Content-Length Pflicht (fehlt sie, 411), Fotos dürfen chunked kommen (ob Apples Upload-Jobs die Länge senden, ist nicht belegt; ohne Endblock bleibt nichts liegen); unter 5 GB freiem Platz 507, Platte voll beim Ablegen 507, unmöglicher Name 400; neue Dateien 0600, neue Ordner 0700; Dateiname höchstens 200 UTF-8-Bytes. Ausnahmen in den Routen liefern leer 500 (kein Stacktrace); ist `tresor/aktuell.json` nicht lesbar oder kaputt, antwortet der Dienst 500 und schreibt nichts.

Pfade: nur relativ, normalisiert, `realpath` muss in `HEIMHERZ_DATEIEN` liegen (keine `..`, keine Symlinks hinaus). Tests für jeden Ausbruchsversuch.

## 7. Modul `pc-werkzeug`

`bin/heimherz` (Bun-Skript, Link nach `~/.local/bin/heimherz`).

- `heimherz einrichten`: legt Ordner an, erzeugt K und legt ihn mit `systemd-creds --user encrypt --name=heimherz` in `~/.local/share/heimherz/schluessel.cred` ab (Muster `claude-bw`). Nie in Klartext auf Platte, nie in stdout.
- `heimherz koppeln [NAME]`: neues Geräte-Token, QR mit `heimherz://koppeln?url=…&token=…&schluessel=…` als PNG in `$XDG_RUNTIME_DIR/heimherz/koppeln.png` (0600), öffnet es für Ahmed (`claude-start --fuer-ahmed imv …`) und löscht es nach 5 Minuten oder sobald das Gerät sich meldet. Ausgabe nur "QR offen, wartet auf Handy".
- `heimherz import bitwarden`: liest `bw export --format json --raw` mit der Sitzung von `claude-bw` direkt in den Speicher, wandelt um (Logins, Notizen, TOTP, URIs), führt mit dem Tresor zusammen, lädt hoch. Ausgabe nur Zahlen ("312 Logins, 4 Notizen, 0 übersprungen").
- `heimherz export bitwarden DATEI`: Bitwarden-JSON (unverschlüsselt) mit Rechten 0600. Nur auf Ahmeds Wort.
- `heimherz liste [SUCHE]`: id, name, benutzer, hosts, totp ja/nein. Nie Passwörter.
- `heimherz status`: Dienst, rev, Geräte, letzte Meldung je Gerät, Fotos heute.
- `heimherz geraet weg ID`: Token widerrufen.

## 8. Modul `ios-grundgeruest`

Wie Bahnherz (`~/projects/bahnherz-ios`): `project.yml`, `Gemeinsam/`, `Heimherz/Sources/Module/<Modul>`, Tests mit JSON-Fixtures, Design-System von Bahnherz übernommen (Farben eigenes Thema: warmes Grün statt Pink, Maskottchen ein kleines Haus mit Herz).

Targets: `Heimherz` (App), `HeimherzAutoFill` (Credential Provider), `HeimherzFotos` (Photos Background Upload Extension). Bundle IDs `com.onlyus.heimherz`, `.autofill`, `.fotos`. App Group `group.com.onlyus.heimherz`. Schlüsselbund-Gruppe `$(AppIdentifierPrefix)com.onlyus.heimherz`.

Gemeinsam/:
- `Tresor/` Modelle, `Umschlag` (AES-GCM), `Zusammenfuehren`, `TOTP` (aus `tresor-format`).
- `Schluessel/` K im Schlüsselbund, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, Zugriffsschutz `.userPresence` (Face ID oder Code), Gerät-Token getrennt ohne Face ID.
- `Ablage/` verschlüsselter Tresor-Cache als Datei in der App Group (nur Umschlag, nie Klartext auf Platte).
- `Netz/` `HeimClient` (async, URLSession, Bearer, Fehler als Typ), Server-URL aus dem Koppeln.
- `Koppeln/` QR lesen (VisionKit `DataScannerViewController`), URI prüfen, speichern, Testanfrage `GET /v1/status`.

Tabs: Passwörter, Fotos, Dateien, Mehr (Status, Koppeln, Build-Ablauf, Sperre).

### Grundgerüst (gebaut, T4)

Alle Typen sind `internal`: `Gemeinsam/` wird in App, `HeimherzAutoFill` und `HeimherzFotos` einkompiliert (je eigenes Modul), `@testable import Heimherz` in den Tests. Kein `public` nötig. Klartext (Passwörter, K) lebt nur im Speicher.

| Datei in `Gemeinsam/` | Typen und Signaturen |
|---|---|
| `Kennungen.swift` | `enum Kennungen { appGruppe, schluesselbundDienst, urlSchema, gruppenOrdner() -> URL? }` |
| `Tresor/JSONWert.swift` | `enum JSONWert: Codable, Sendable, Equatable` (`null, bool, zahl, text, liste, objekt`), `jsonText`, `textLiteral`, `objektText(vorn:rest:)` (eigener Schreiber, Text wie `JSON.stringify`) |
| `Tresor/Eintrag.swift` | `struct Eintrag: Codable, Sendable, Equatable, Identifiable` mit `id, art, name, benutzer, passwort, urls, totp, notiz, favorit, geaendert, geloescht, unbekannt: [String: JSONWert]`; `init(id:art:name:benutzer:passwort:urls:totp:notiz:favorit:geaendert:geloescht:unbekannt:)`, `json()`, `alsGrabstein(geaendert:)`, `Eintrag.artLogin/artNotiz` |
| `Tresor/Tresor.swift` | `struct Tresor: Codable, Sendable, Equatable` (`eintraege`, `unbekannt`), `Tresor.aus(daten:)`, `json()`, `jsonDaten`, `lebendige` |
| `Tresor/Umschlag.swift` | `struct Umschlag` (`v, rev, nonce, daten`), `Umschlag.verschliesse(_:schluessel:rev:nonce:)`, `oeffne(schluessel:)`, `istGueltigeForm`, `Umschlag.aad`; `enum TresorSchluessel { aus(_ roh: Data) throws -> SymmetricKey }` |
| `Tresor/Zusammenfuehren.swift` | `enum Zusammenfuehren { zusammenfuehren(_:_:jetzt:) -> Tresor, gewinnt(_:_:) -> Bool, grabsteinTage }` |
| `Tresor/Zeit.swift` | `enum Zeit { millis(iso:) -> Int64?, iso(_ Date), iso(millis:) }` (UTC, Millisekunden) |
| `Tresor/TOTP.swift` | `struct TOTPEinstellung`, `enum TOTP { einstellung(aus:) -> TOTPEinstellung?, code(_:zeit:), code(_:datum:), restsekunden(_:zeit:), base32(_:) }` |
| `Tresor/TresorFehler.swift` | `enum TresorFehler` mit `nutzerText` |
| `Tresor/TresorDienst.swift` | `actor TresorDienst { init(ablage:client:jetzt:), lokal(schluessel:), speichereLokal(_:schluessel:), abgleichen(lokal:schluessel:) async throws -> AbgleichErgebnis }`, `enum AbgleichErgebnis { abgeglichen(Tresor, rev:), nurLokal(Tresor, grund: HeimFehler) }` |
| `Schluessel/Schluesselbund.swift` | `struct Schluesselbund { live, init(speicher:), speichereSchluessel(_:), ladeSchluessel(kontext:) async throws -> SymmetricKey?, speichereGeraet(_:), ladeGeraet() -> Geraet?, vergiss() }`, `struct Geraet { url, token }`, `struct EntsperrKontext`, `protocol KeychainSpeicher`, `SecItemSpeicher` |
| `Ablage/TresorAblage.swift` | `struct TresorAblage { init(ordner:), appGruppe(), lade() -> Umschlag?, speichere(_:), loesche() }` |
| `Netz/HeimClient.swift` | `struct HeimClient { init(basis:token:sitzung:), aus(_ bund:), anfrage(_:_:abfrage:), status(), tresorHolen(), tresorSchreiben(_:ifMatch:) -> TresorSchreiben, fotosBekannt(), fotoHochladenAnfrage(kennung:ressource:aufnahme:dateiname:) -> URLRequest, dateienListe(pfad:), dateiLaden(pfad:nach:), dateiHochladen(pfad:von:), inPapierkorb(pfad:) }`; `ServerStatus`, `BekanntesFoto`, `DateiInfo`, `TresorSchreiben { gespeichert, konflikt(aktuell:) }`, `enum HeimFehler` (`nutzerText`, `istNetzproblem`) |
| `Koppeln/KoppelLink.swift` | `KoppelLink.lese(_:) throws -> KoppelDaten`, `Koppeln.koppeln(link:bund:sitzung:) async throws -> ServerStatus` (speichert erst nach erfolgreichem `GET /v1/status`), `KoppelFehler` |
| `Design/` | `Palette`/`Color.*` (warmes Grün, Kontrast per Test), `Abstand`, `Rundung`, `HausherzView(stimmung:groesse:beschriftet:)` |

App (`Heimherz/Sources/`): `AppUmgebung` (`@Observable`, per `@Environment(AppUmgebung.self)`: `bund`, `ablage`, `geraet`, `status`, `client() throws -> HeimClient`, `tresorDienst() -> TresorDienst`, `koppeln(link:)`, `entkoppeln()`), `AppSperre` (Face ID nach 5 min), `BuildAblauf` (`hinweis(buildDatum:jetzt:)`, Info.plist-Wert `HeimherzBuildDatum`), Bausteine `HeroKarte`, `ListenKarte`, `StatusChip`, `LeerZustand`, `FehlerKarte`, `WertZeile`.

Einstieg je Modul: `ios-passwoerter` ersetzt `Heimherz/Sources/Module/Passwoerter/PasswoerterTabView.swift` (K per `bund.ladeSchluessel()`, Abgleich über `umgebung.tresorDienst()`); `ios-fotos` ersetzt `Module/Fotos/FotosTabView.swift` und `HeimherzFotos/Sources/FotosErweiterung.swift`; `ios-dateien` ersetzt `Module/Dateien/DateienTabView.swift`; `ios-autofill` ersetzt `HeimherzAutoFill/Sources/CredentialProviderViewController.swift` (Schlüssel mit `EntsperrKontext`, Tresor per `TresorAblage.appGruppe()` und `TresorDienst.lokal`).

Foto-Erweiterung (iOS 26.1, aus Apples Doku "Uploading asset resources in the background"): Protokoll `PHBackgroundResourceUploadExtension` (`process()`, `notifyTermination()`), Erweiterungspunkt `com.apple.photos.background-upload` (`EXAppExtensionAttributes`), XcodeGen-Typ `extensionkit-extension`, im App-Bundle unter `Extensions/`. Info.plist-Schlüssel `BackgroundUploadURLBase` (feste Basis-URL des Dienstes, Build-Einstellung `HEIMHERZ_UPLOAD_URL_BASE`, im TestFlight-Lauf aus dem Secret gleichen Namens). Ein eigenes Entitlement nennt Apple nicht. Die App muss `PHPhotoLibrary.shared().setUploadJobExtensionEnabled(true)` nach voller Fotos-Erlaubnis rufen. Laut Doku fragt das System den Upload-Endpunkt vorab mit `OPTIONS` ab (Antwort `501` = kein Resumable Upload) und erwartet bei Resumable Uploads `104`; der PC-Dienst kennt `OPTIONS` noch nicht (T6, T9 prüfen).

## 9. Modul `ios-passwoerter`

Liste mit Suche (Name, Benutzer, Host), Favoriten oben. Detail: Benutzer und Passwort kopieren (Zwischenablage `localOnly`, Ablauf 60 s), Passwort zeigen nach Face ID, TOTP-Code mit Ring. Neu und Bearbeiten, Löschen als Grabstein. Generator (Länge 8 bis 64, Ziffern, Zeichen, Wortgruppen-Modus). Abgleich: beim Öffnen, nach jeder Änderung, per Ziehen; Ablauf `GET` → entschlüsseln → zusammenführen → verschlüsseln → `PUT If-Match`; 409 = nochmal (höchstens 3). Nach jedem Abgleich Identitäten an `ASCredentialIdentityStore` geben (nur Host, Benutzer, id). App sperrt nach 5 min im Hintergrund.

### Gebaut (T5, Abweichungen und Festlegungen)

- Dateien: `Heimherz/Sources/Module/Passwoerter/` (`TresorStore` = Klartext nur im Speicher, `PasswoerterTabView`, `EintragDetailView`, `EintragFormular`, `GeneratorBlatt`, `Entwurf`, `Hilfen`), geteilt in `Gemeinsam/AutoFill/` (`EintragSuche`, `AutoFillIdentitaeten`, `PasswortGenerator`, `Wortliste`).
- Sperren: Der Store leert Tresor und Schlüssel, sobald die App sperrt oder entkoppelt wird; Ergebnisse von Aufgaben, die vor der Sperre starteten, werden verworfen (`sperrZaehler`).
- Änderungen werden erst lokal verschlüsselt gespeichert (`speichereLokal`), dann abgeglichen; Abgleich beim Öffnen, nach jeder Änderung, beim Zurückkehren in die App und per Ziehen. "Zuletzt abgeglichen" bleibt über Neustarts (UserDefaults, nur die Zeit).
- Passwort zeigen: Geräteabfrage (`LAContext` `.deviceOwnerAuthentication`), danach 30 s sichtbar. Kopieren: `UIPasteboard` mit `localOnly` und Ablauf 60 s.
- Generator: Zeichen-Modus (8 bis 64, Ziffern, Sonderzeichen `!#$%&*+-=?@_`, von jeder Klasse mindestens eins), Wortgruppen-Modus (3 bis 8 Wörter, optional Zahl, Trenner). Wortliste (1180 Wörter, kleingeschrieben, ASCII) steht im Quelltext (`Wortliste.swift`) statt als Bundle-Ressource, weil die AutoFill-Erweiterung dasselbe Modul `Gemeinsam` nutzt und kein Zugriff auf das App-Bundle hat. Zufall: `SystemRandomNumberGenerator`.
- Identitäten (`AutoFillIdentitaeten.baue`): je lebendigem Login mit Benutzer und je Host der URLs eine `ASPasswordCredentialIdentity` (`.domain`, `recordIdentifier` = Eintrag-id, `rank` 1 bei Favorit); bei lesbarem TOTP zusätzlich eine `ASOneTimeCodeCredentialIdentity`. Nie Passwort oder TOTP-Geheimnis.
- Hostzuordnung: gleicher Host oder Unterdomain an der Punktgrenze (`m.example.com` passt zu `example.com`, `evilexample.com` nicht). Keine Public-Suffix-Liste (`shortcut:` im Code).

## 10. Modul `ios-autofill`

`ASCredentialProviderViewController`:
- Passwort: `prepareCredentialList(for:)` mit Liste passend zur Domain, `provideCredentialWithoutUserInteraction` nur wenn K ohne Abfrage lesbar ist, sonst `ASExtensionError.userInteractionRequired`.
- Einmalcode (ab iOS 18): `ASOneTimeCodeCredentialIdentity` für Einträge mit TOTP.
- Speichern und Generieren (ab iOS 26.2, API-Namen vor dem Bau in Apple-Doku prüfen): neuer Eintrag landet im Cache und wird beim nächsten App-Start abgeglichen (Erweiterung macht kurz selbst `PUT`, wenn der PC erreichbar ist).
- Info.plist: `ASCredentialProviderExtensionCapabilities` mit `ProvidesPasswords`, `ProvidesOneTimeCodes`, `SupportsCredentialExchange` (für späteren iCloud-Import).
- Speichergrenze der Erweiterung beachten (kein großes Laden, Tresor nur einmal entschlüsseln).

### Gebaut (T8, Abweichungen und Festlegungen)

- Dateien: `HeimherzAutoFill/Sources/` (`CredentialProviderViewController` übersetzt nur zwischen System und Modell, `AutoFillAnsichten` = SwiftUI aus `Gemeinsam/Design`), Ablauf testbar in `Gemeinsam/AutoFill/` (`AutoFillSitzung`, `AutoFillModell`, `PasswortSpeichern`, `PasswortVorschlaege`).
- `provideCredentialWithoutUserInteraction` und `performWithoutUserInteractionIfPossible(savePasswordRequest:)` melden immer `userInteractionRequired`: K liegt mit `.userPresence` im Schlüsselbund und ist ohne Face ID nie lesbar. Der Weg ist darum immer `prepareInterfaceToProvideCredential(for:)` (Vorschlagsleiste: ein Face ID, dann direkt zurück ohne Tippen) oder `prepareCredentialList`.
- Ein Face ID je Aufruf: ein `EntsperrKontext` je `AutoFillSitzung`, der Tresor wird einmal aus dem verschlüsselten Cache geöffnet und nur im Speicher gehalten.
- Speichern (iOS 26.2, belegt in der Apple-Doku): `performWithoutUserInteractionIfPossible(savePasswordRequest:)`, `prepareInterface(for: ASSavePasswordRequest)`, `completeSavePasswordRequest(completionHandler:)`; Info.plist `SupportsSavePasswordCredentials`. Bei `event == .userInitiated` und neuem Konto wird sofort gesichert, sonst fragt eine Karte "In Heimherz sichern?". Gleicher Benutzer und passender Host mit anderem Passwort fragt immer nach ("Passwort aktualisieren?"). Gleiches Passwort ist schon da: nichts tun. Lokal verschlüsselt speichern, dann höchstens 6 s mit dem PC abgleichen, danach Identitäten setzen.
- Passwort-Vorschläge (iOS 26.2): `performWithoutUserInteraction(generatePasswordsRequest:)`, `completeGeneratePasswordRequest(results:completionHandler:)`, `ASGeneratedPassword(kind:value:)` mit `.strong`, `.alphanumeric`, `.passphrase`; Info.plist `SupportsGeneratePasswordCredentials` und `SupportsGeneratePasswordCredentialsWithUI` = false (keine eigene Oberfläche, das System zeigt die Auswahl). Es werden nur `minlength` und `maxlength` der Seitenregeln beachtet (`shortcut:` im Code); Vorschläge, die länger als `maxlength` wären, entfallen.
- Einstellungen: `ShowsConfigurationUI` = true, `prepareInterfaceForExtensionConfiguration` zeigt einen kurzen Hinweis, `completeExtensionConfigurationRequest()` schließt.
- `SupportsCredentialExchange` ist nicht gesetzt: nichts dahinter gebaut (SPEC 2: iCloud-Import offen). Nachziehen, wenn der Import kommt.
- Die Passwörter-App mischt vor jedem Schreiben und Abgleichen den Cache-Stand ein, falls die Erweiterung zwischendurch gespeichert hat. Ein gleichzeitiges Schreiben beider Prozesse im selben Augenblick ist nicht abgesichert (kleines Fenster, der Merge holt es beim nächsten Abgleich nach, solange der Eintrag in einer der beiden Fassungen steht).

## 11. Modul `ios-fotos`

- Erlaubnis Fotos (voller Zugriff). Abgleich: alle `PHAsset`, deren Kennung nicht in `GET /v1/fotos/bekannt` steht; je Ressource (`PHAssetResource`: Foto, gepaartes Video, Video, bearbeitete Fassung nicht) Export per `PHAssetResourceManager.writeData` in eine Temp-Datei, dann Hintergrund-`URLSession` `uploadTask(fromFile:)`. Kennung = SHA-256 von `localIdentifier`, b64url, 43 Zeichen.
- Erweiterung `HeimherzFotos`: `PHBackgroundResourceUploadExtension` (iOS 26.1), erzeugt `PHAssetResourceUploadJob` mit `URLRequest` auf `PUT /v1/fotos/…`. Ein- und Ausschalten in der App. Simulator geht nicht, nur am Gerät.
- Anzeige: Fotos gesamt, am PC, offen, letzte Übertragung, Fehler in Klartext. Nur WLAN als Schalter (Standard an, Videos immer nur WLAN).
- Nie etwas in der Mediathek löschen oder ändern.

Gebaut (25.10.): Server antwortet auf `OPTIONS /v1/fotos/…` ohne Token mit 501 (kein Resumable Upload, Apple-Weg) und nimmt POST wie PUT; Teil-Uploads 400. Ressourcen `foto-N`, `video-N`, `live-N`, `alternative-N`, `ton-N`; bearbeitete Fassungen gehen nicht mit (später). `Gemeinsam/Fotos/` teilt Kennung, Plan und Stand (`fotos-stand.json` in der App Group) zwischen App und Erweiterung; die Erweiterung hat kein Netz zum Abfragen und liest `bekannt` aus dem Stand. Vor iOS 26.5 merkt sie eingereichte Jobs selbst (3 Tage), vor 26.4 kein `job.error`. Ohne WLAN wartet die App statt iCloud-Originale mobil zu laden. Kein `handleEventsForBackgroundURLSession`: alte Transfers werden beim nächsten Öffnen des Tabs eingesammelt.

## 12. Modul `ios-dateien`

Ordnerliste, Vorschau mit QuickLook (Download in Cache, Range wird nicht gebraucht), Teilen (`ShareLink`), Hochladen aus Dateien-App (`fileImporter`) und Fotos, in den Papierkorb legen mit Rückfrage. Kein Offline-Spiegel.

Gebaut (25.10.): Datei antippen öffnet ein Blatt mit Ansehen, Teilen, Papierkorb; Papierkorb auch per Langdruck. Fotos-Auswahl lädt Dateien (nicht Data), Name `Foto JJJJ-MM-TT HH-MM-SS.ext`, bis 20 auf einmal.

## 13. Modul `freigabe`

1. PC: `systemd --user` Dienst `heimherz.service` (`Restart=on-failure`), `loginctl enable-linger` ist schon an oder wird gesetzt, `tailscale serve`. HTTPS im Tailnet einschalten (Admin-Konsole, DNS → HTTPS Certificates; Agent im Agenten-Chrome, Login fehlt = Lovea-Notiz).
2. Apple: Bundle IDs mit AutoFill Credential Provider und App Groups per API; App Group und App-Eintrag im Portal (einmal Ahmeds Login im Agenten-Chrome, danach klickt der Agent); Profile, Secrets, TestFlight wie Bahnherz (`signing/`).
3. Erst-Einrichtung mit Ahmed (Lovea-Notiz): App aus TestFlight, `heimherz koppeln`, QR scannen, iPhone Einstellungen → Allgemein → AutoFill → Heimherz an (iCloud-Passwörter aus). Bitwarden bleibt 4 Wochen installiert.

## 14. Nicht im ersten Build (später, gleiche Liste in `docs/ideas/heimherz.md`)

- Passkeys (`ASPasskeyCredentialRequest`, P-256): eigener Schritt nach 2 Wochen ohne Fehler.
- Import aus iCloud-Passwörtern per Credential Exchange (`ASCredentialImportManager`): nur wenn iOS Heimherz als Ziel anbietet.
- File Provider (Heimherz in der Dateien-App), Offline-Ordner.
- Google Drive einmal holen (`rclone copy`).
- Agent füllt aus Heimherz statt Bitwarden (`claude-bw` umstellen).
- Offsite-Sicherung (restic, Kauf macht Ahmed).
- Annika als zweite Nutzerin.

## 15. Commands

```
# PC (lokal)
~/.bun/bin/bun test                         # tresor-format, pc-dienst, pc-werkzeug
~/.bun/bin/bun server/index.ts              # Dienst lokal (Port 8790)
bash scripts/check-schnell.sh               # Syntax, JSON, Shell, actionlint, Privat-Check
# iOS (nur CI, kein Mac)
bash scripts/ci-fenster.sh                  # öffentlich, Push, ios-ci.yml, wieder privat (im Hintergrund)
gh workflow run testflight.yml --repo Tobito320/heimherz-ios --ref main
```

## 16. Projektstruktur

```
SPEC.md CONTEXT.md CONSTRAINTS.md AGENTS.md CLAUDE.md
fixtures/            gemeinsame Fixtures (tresor, merge, totp), von Bun und XCTest gelesen
server/              pc-dienst (index.ts, *.test.ts)
lib/                 tresor-format in TS (umschlag.ts, zusammenfuehren.ts, totp.ts + Tests)
bin/heimherz         pc-werkzeug
Gemeinsam/           Swift, von App und Erweiterungen geteilt
Heimherz/Sources/    App (Module/Passwoerter, Fotos, Dateien, Mehr, Design)
Heimherz/Tests/
HeimherzAutoFill/ HeimherzFotos/
signing/ scripts/ .github/workflows/ docs/ tasks/
```

## 17. Code-Stil

Wie Bahnherz (`~/projects/bahnherz-ios/CLAUDE.md`): Bezeichner ASCII Deutsch, Oberflächentexte Deutsch mit Umlauten, reine Logik als `enum` mit `static func`, Zustand `@MainActor @Observable final class`, Daten `Sendable`. TS: kleine Funktionen, keine Klassen ohne Grund.

```ts
export async function oeffne(umschlag: Umschlag, schluessel: CryptoKey): Promise<Tresor> {
  const klar = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64(umschlag.nonce), additionalData: AAD }, schluessel, b64(umschlag.daten));
  return JSON.parse(new TextDecoder().decode(klar));
}
```

## 18. Teststrategie

- `bun test`: Umschlag rund, falscher Schlüssel scheitert, Merge-Fixtures, TOTP-RFC-Vektoren, jede Server-Route (Auth, 409, Verlauf, Pfad-Ausbruch, Foto doppelt, Papierkorb), Import aus Bitwarden-Beispieldatei (erfundene Daten).
- XCTest in CI: dieselben Fixtures (Umschlag aus TS lesen, Merge, TOTP), Koppel-URI, Client gegen Fake-Server (`URLProtocol`).
- Ende-zu-Ende lokal: Dienst starten, `heimherz` gegen ihn, Umschlag aus Swift-Fixture.
- Am Gerät (Ahmed, nach TestFlight): AutoFill in Safari, Einmalcode, Speichern, 20 Fotos, eine PDF.

## 19. Boundaries

- Immer: Test zuerst; Geheimnisse nur im Speicher, Schlüsselbund oder `systemd-creds`; nie Klartext-Passwort in stdout, Log, Datei (außer `export` auf Ahmeds Wort), Commit oder Kontext eines Agenten; Fotos nie am Handy löschen; Dateien nur in den Papierkorb.
- Erst fragen (Lovea-Notiz): Bitwarden abschalten, iCloud-Passwörter abschalten, irgendetwas löschen.
- Nie: Daten an Dritte, Dienst ins offene Internet (Funnel, Cloudflare), eigene Krypto-Primitive (nur CryptoKit und WebCrypto), Kauf von Speicher, echte Tresordaten in Tests oder Fixtures.

## 20. Erfolgskriterien

1. `bun test` grün, CI grün, TestFlight-Build am Handy.
2. Nach Koppeln und Import: Safari bietet ein Konto aus Heimherz an und füllt es aus; ein TOTP-Code wird gefüllt.
3. Neuer Eintrag am Handy ist innerhalb einer Minute in `heimherz liste`.
4. Flugmodus: AutoFill geht weiter.
5. 20 Testfotos (mit Live Photo und Video) liegen vollständig und mit gleicher Größe am PC; zweiter Abgleich lädt nichts doppelt.
6. Eine PDF vom PC lässt sich am Handy öffnen und teilen; eine Datei vom Handy liegt danach im Ordner.
7. Ohne Token: jede Route 401; Pfad `../` wird abgelehnt.

## 21. Annahmen (ohne Rückfrage entschieden)

- Name "Heimherz" (passt zu Bahnherz, Aboherz). Repo `~/projects/heimherz-ios`, Link `~/code/heimherz-ios`, GitHub `Tobito320/heimherz-ios` privat.
- Tresor-Quelle ist Bitwarden (Import am PC); iCloud-Passwörter nur, falls der Import am Handy möglich ist.
- Server ist eine dumme Ablage: er sieht nie Klartext. Den Schlüssel hat nur das CLI am PC und das Handy.
- Mindest-iOS 26.1 (Foto-Erweiterung). Ahmeds iPhone hat 26.1 oder neuer (unsicher, beim Koppeln prüfen).
- Fotos landen unter `~/Heimherz/Fotos`, nicht in einem bestehenden Bilder-Ordner.

## 22. Offene Fragen (blockieren nicht)

- Bleibt Bitwarden nach 4 Wochen als Ersatz liegen oder wird gekündigt? Entscheidet Ahmed.
- Offsite-Kopie kaufen? Entscheidet Ahmed.
