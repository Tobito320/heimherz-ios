# SPEC: Heimherz

Sichtbarer Name: **Heimcloud** (Ahmed 25.10.: erst "Ohne herz" → Heim, dann "Das name sollte zu der app passen zu was sie macht. Also wie icloud." → "Heimcloud ist gut"). Home-Bildschirm, Texte in der App und Rechte-Texte sagen "Heimcloud", App-Store-Connect-Name "Heimcloud". Intern bleibt alles `heimherz` (Bundle IDs, App Group, Repo, Typen, CLI, Dienst, Ordner `~/Heimherz`, AAD).

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
- Hintergrund-Upload der Fotos entscheidet iOS. Die Foto-Erweiterung von iOS 26.1 ist laut Apple-Forum wacklig (26.2 löst teils nicht aus). Darum mehrere Wege: Abgleich per Knopf (Start/Anhalten in Stücken, `BGContinuedProcessingTask` trägt ihn weiter), Nachtlauf (`BGProcessingTask`) und Erweiterung. Kein Auto-Start beim Öffnen mehr (sonst startet er nach "Anhalten" wieder; W-003).
- iCloud-Passwörter-Import per Credential Exchange: iOS listet Ziel-Apps nach eigenen Regeln, ob Heimherz erscheint, ist offen (unsicher).
- Passkeys: Phase 2, nicht im ersten Build (Abschnitt 14).
- PC aus = kein Abgleich. Tailscale weckt den PC nicht.
- Entsperr-Fenster (W-009, 25.10.): Nach einem Face ID in App oder Erweiterung liegt eine zweite Kopie von K im Schlüsselbund, ohne `.userPresence`, `WhenUnlockedThisDeviceOnly`, gleiche Zugriffsgruppe (Original bleibt hinter Face ID). Sie trägt den Zeitpunkt des Öffnens und gilt nur, solange der höchstens `entsperrDauer` (Standard 5 Minuten, "Jedes Mal" = nie) zurückliegt; sie wird bei jedem Lesen geprüft und gelöscht bei Ablauf, `.aus`, kürzerer Dauer, zurückgestellter Uhr, kaputtem Inhalt, Sperren der App, Neu-Koppeln und Entkoppeln. Bewusst angenommen: Innerhalb des Fensters kann jeder mit entsperrtem Handy ausfüllen und die App öffnen, wie bei Bitwarden mit Zeitlimit. K liegt in dieser Zeit auch ohne `.userPresence` im Schlüsselbund, geschützt nur durch Gerätesperre und Sandbox (andere Apps kommen nicht heran). Die Kopie hält bis zum nächsten Lesen oder Öffnen der App noch ein paar Minuten über das Fenster hinaus im Schlüsselbund, ist dann aber wertlos (Zeitprüfung beim Lesen) und wird beim nächsten Zugriff gelöscht. Warum nicht `LAContext.touchIDAuthenticationAllowableReuseDuration`: nach Apple-Doku gilt es je Kontext im Speicher des Prozesses, höchstens 5 Minuten, trägt nicht in einen anderen Prozess und nicht über 5 Minuten (Fenster bis 1 Stunde); am Gerät nicht geprüft, nicht eingebaut.
- Schlüssel am PC: `systemd-creds --user` schützt gegen eine ausgebaute Platte (TPM2), nicht gegen Programme, die als `tobi` laufen. Jeder Prozess dieses Nutzers (auch ein Agent mit Bash) könnte K entschlüsseln. Bewusst angenommen wie bei `claude-bw` (`master.cred`); Regel: Agenten lesen K nie.

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
Unbekannte Felder bleiben beim Lesen und Schreiben erhalten (Vorwärts-Verträglichkeit). Gelöschte Einträge bleiben als Grabstein (`geloescht: true`) 90 Tage. Löschen in der App behält die Felder ("Gelöscht", 30 Tage wiederherstellbar, Wiederherstellen = `geloescht: false` mit neuem `geaendert`); "Endgültig löschen" und die Bereinigung nach 30 Tagen leeren Felder und unbekannte Felder (Grabstein bleibt, neuer `geaendert`). Der Merge ändert sich dadurch nicht (neueres `geaendert` gewinnt), AutoFill und Listen lesen nur lebendige Einträge.

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
| `GET /v1/dateien?pfad=` | Ordnerliste `[{name, ordner, groesse, geaendert, anzahl?}]` (`anzahl` nur bei Ordnern: Einträge darin ohne eigene Temp-Dateien, für "12 Objekte") |
| `GET /v1/dateien/suche?q=&pfad=` | Suche im Namen, rekursiv ab `pfad` (leer = Wurzel): `[{pfad, name, ordner, groesse, geaendert}]`, höchstens 200 (siehe unten) |
| `GET /v1/dateien/vorschau?pfad=&px=` | Vorschaubild als JPEG, `px` 120 bis 600 (Standard 240); 404 bei anderem Typ oder wenn kein Bild entsteht (siehe unten) |
| `GET /v1/datei?pfad=` | Download mit Range |
| `PUT /v1/datei?pfad=` | Upload (überschreibt nie: bei Namensgleichheit ` (2)` anhängen) |
| `POST /v1/datei/papierkorb` `{pfad}` | in den Linux-Papierkorb (`trash-put`), nie löschen |
| `GET /v1/symbol?host=` | Symbol der Webseite für die Listen am Handy: 200 Bild, 404 keins, 400 ungültiger Host (siehe unten) |

Uploads: bei Dateien ist Content-Length Pflicht (fehlt sie, 411), Fotos dürfen chunked kommen (ob Apples Upload-Jobs die Länge senden, ist nicht belegt; ohne Endblock bleibt nichts liegen); unter 5 GB freiem Platz 507, Platte voll beim Ablegen 507, unmöglicher Name 400; neue Dateien 0600, neue Ordner 0700; Dateiname höchstens 200 UTF-8-Bytes. Ausnahmen in den Routen liefern leer 500 (kein Stacktrace); ist `tresor/aktuell.json` nicht lesbar oder kaputt, antwortet der Dienst 500 und schreibt nichts.

Foto-Tempo (Runde 4, T16): Die App schickt bei jedem Foto-Upload Kopfzeilen nur mit Zahlen oder festen Stichwörtern: `X-Heim-Export-Ms` (Dauer des PhotoKit-Exports), `X-Heim-Warte-Ms` (vom fertigen Export bis zum Upload-Start), `X-Heim-Aktiv` (laufende Uploads, diesen mitgezählt), `X-Heim-Exporte` (laufende Exporte), `X-Heim-Vordergrund` (1/0), `X-Heim-Durchgang` (`lokal`/`icloud`), `X-Heim-Session` (`vorder`/`hinter`). `server/tempo.ts` schreibt je Upload eine Zeile nach `foto-tempo.jsonl` im Datenordner (Rechte 0600, höchstens 20.000 Zeilen, dann Umbenennen nach `.1` und neu beginnen): `{zeit, bytes, empfangMs, gesamtMs, ergebnis (neu|schon|abbruch), art (foto|video|live|alternative|ton|andere), exportMs, warteMs, aktiv, exporte, vordergrund, durchgang, session}`. Ungültige Kopfzeilen werden `null`; Namen, Kennungen und Inhalte stehen nie drin; ein Fehler beim Schreiben bricht nie einen Upload ab. `empfangMs` ist die Zeit am Server vom Eingang der Anfrage bis zum letzten Byte auf der Platte, `gesamtMs` reicht bis zur Antwort (Ablegen und SQLite-Insert eingerechnet).

Symbole (`server/symbol.ts`): Der PC holt das Bild direkt von der Seite (`https://<host>/apple-touch-icon.png`, sonst `<link rel=icon>` im HTML, sonst `/favicon.ico`), kein Drittdienst. Höchstens 256 KB (Abbruch beim Streamen), Typ nach den ersten Bytes (PNG, JPEG, GIF, WebP, ICO; kein SVG), je Anfrage 5 s und insgesamt 10 s, höchstens 4 gleichzeitig und gleiche Hosts zusammengelegt. Cache `symbole/` im Datenordner (Dateiname = SHA-256 des Hosts, 0600/0700), 30 Tage, auch "kein Symbol" (bei Netzfehler nur 1 Stunde). Schutz vor SSRF: nur gültige öffentliche Hostnamen (keine IP, kein Port, nicht `.local`/`.ts.net`/`.internal`/…), alle aufgelösten Adressen müssen öffentlich sein (nicht 0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.168/16, Multicast und Reserviertes; IPv6 `::1`, `fc00::/7`, `fe80::/10`, eingebettetes IPv4), die Verbindung geht genau an die geprüfte Adresse (`node:https` mit `lookup`), nur https auf Port 443, Weiterleitungen (höchstens 3) und `<link>`-Ziele werden jedes Mal neu geprüft. Tests mit austauschbarem Auflöser und Holer in `server/symbol.test.ts`.

Dateisuche (W-031, `server/dateien.ts`): `q` ohne Groß/klein und ohne Umlaut-Unterschied (ä = ae, ö = oe, ü = ue, ß = ss; zerlegte Zeichen werden zuerst zusammengesetzt), mehrere Wörter = alle müssen im Namen vorkommen; leere Suche, nur Leerzeichen oder über 200 Zeichen = 400, Datei als `pfad` = 400. Treffer: Ordner zuerst, dann beginnt mit dem ersten Wort vor enthält, dann neu vor alt; höchstens 200. `pfad` im Treffer ist relativ zur Wurzel und endet mit dem Namen, `ordner` ist wie in der Liste ein Wahrheitswert (den Ordner des Treffers liest die App aus `pfad`). Versteckte Namen (`.`) und `*.teil` erscheinen nie. Symlinks innerhalb der Wurzel sind Treffer, werden aber nie betreten (keine Schleifen); Symlinks hinaus bleiben unsichtbar. Der Durchlauf bricht nach 200.000 Einträgen ab.

Vorschau (`server/vorschau.ts`): Bild (jpg, jpeg, png, gif, webp, heic, heif, tif, tiff, bmp) mit `magick`, PDF erste Seite mit `pdftoppm`, Video (mp4, mov, m4v, mkv, avi, webm) ein Bild bei 1 s mit `ffmpeg` (kürzere Videos: erstes Bild); alles andere 404, Ordner 400. Programme laufen mit Argumentliste (`Bun.spawn`, nie über eine Shell): `magick` liest die Datei aus stdin mit ausdrücklichem Format (`png:-[0]`), so deutet kein Dateiname als Option, Muster oder Bildbereich; `pdftoppm` bekommt den Pfad nach `--`; `ffmpeg` `-i file:<absoluter Pfad>`. Je Programm 10 s Zeitlimit, höchstens 2 gleichzeitig, gleiche Anfragen werden zusammengelegt. Ausgabe höchstens 300 KB (Qualität 80, dann 55, dann 35, sonst 404). Cache `vorschau/` im Datenordner (Dateiname = SHA-256 aus Pfad, Größe, mtime und px; 0600/0700, wird nie aufgeräumt: bei Platzmangel den Ordner löschen). Was misslingt, wird bis zum Neustart nicht erneut versucht. Tests mit austauschbarem Erzeuger (`Optionen.vorschau`), die Tests mit echten Programmen laufen nur, wo `magick`, `pdftoppm` und `ffmpeg` da sind.

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
- `heimherz tempo [MINUTEN]` (Standard 10, `bin/tempo.ts`): fasst `foto-tempo.jsonl` zusammen. Das Fenster endet bei der letzten Zeile, nicht bei jetzt. Ausgabe: MB/s und Dateien/s, Ergebnisse (neu, schon da, abgebrochen), Export, Warten und Empfang je als Mittel und p90, Empfang je Upload in MB/s, mittlere Zahl gleichzeitiger Uploads am Server (nahe an `X-Heim-Aktiv` heißt Netz oder Server ist die Grenze, weit darunter heißt die App füttert zu langsam), Anteil Vordergrund, Sitzungen, Durchgänge und Arten.

## 8. Modul `ios-grundgeruest`

Wie Bahnherz (`~/projects/bahnherz-ios`): `project.yml`, `Gemeinsam/`, `Heimherz/Sources/Module/<Modul>`, Tests mit JSON-Fixtures, Design-System von Bahnherz übernommen (Farben eigenes Thema: warmes Grün statt Pink, Maskottchen ein kleines Haus mit Herz).

Targets: `Heimherz` (App), `HeimherzAutoFill` (Credential Provider), `HeimherzFotos` (Photos Background Upload Extension). Bundle IDs `com.onlyus.heimherz`, `.autofill`, `.fotos`. App Group `group.com.onlyus.heimherz`. Schlüsselbund-Gruppe `$(AppIdentifierPrefix)com.onlyus.heimherz`.

Gemeinsam/:
- `Tresor/` Modelle, `Umschlag` (AES-GCM), `Zusammenfuehren`, `TOTP` (aus `tresor-format`).
- `Schluessel/` K im Schlüsselbund, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, Zugriffsschutz `.userPresence` (Face ID oder Code), Gerät-Token getrennt ohne Face ID. Dazu für die Entsperr-Dauer eine Fenster-Kopie ohne `.userPresence` (SPEC 2 und 10, W-009); innerhalb des Fensters fragen auch Passwort zeigen, Codes und frühere Passwörter in der App nicht erneut (`GeraeteAbfrage`).
- `Ablage/` verschlüsselter Tresor-Cache als Datei in der App Group (nur Umschlag, nie Klartext auf Platte).
- `Netz/` `HeimClient` (async, URLSession, Bearer, Fehler als Typ), Server-URL aus dem Koppeln.
- `Koppeln/` QR lesen (VisionKit `DataScannerViewController`), URI prüfen, speichern, Testanfrage `GET /v1/status`.

Tabs: Passwörter, Fotos, Dateien, Einstellungen (vorher "Mehr"; PC, Sicherheit, Passwörter, Fotos, Dateien, Über, siehe Abschnitt "Einstellungen").

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

Sicherheit (25.10., nach der Prüfung): Koppeln nimmt nur Hosts auf `.ts.net`, zeigt vorher "Mit <host> koppeln?" (bei schon gekoppeltem Handy mit Warnung, dass der alte Zugang samt Tresor ersetzt wird, und einem Abgleichversuch davor). Entkoppeln versucht vorher einen Abgleich und zeigt sonst "N Änderungen noch nicht am PC"; Fehler des Schlüsselbunds werden angezeigt; die Foto-Erweiterung wird ausgeschaltet. Es gibt kein URL-Schema `heimherz://` mehr (der QR wird nur in der App gescannt; `Kennungen.urlSchema` bleibt für das Lesen des Textes). Bei `.inactive` und `.background` deckt `AppSperre.verdeckt` sofort das Haus über den Inhalt (unabhängig von den 5 Minuten). App-Sperre und Laden von K teilen sich einen `EntsperrKontext` (`AppSperre.kontext`, bei jeder Sperre neu): beim Start nur eine Face-ID-Abfrage.

### Runde 3 (W-007, W-013): aufgeräumt, Schnellaktionen

Jede Seite zeigt nur den Kern; Seltenes liegt im Drei-Punkte-Menü oder auf einer Unterseite, Schalter in den Einstellungen. Passwörter-Start: keine Karte "Aus Apple Passwörter holen" mehr (nur im Menü oben, dort steht auch "Zuletzt abgeglichen: …"), `SyncStatus` zeigt nur Fehler, "PC nicht erreichbar" und "Gleiche ab". Fotos-Tab: Übersicht (Hero, drei Zahlen) und Raster; die drei Schalter und der lange Text "Wie das Sichern läuft" sind in den Einstellungen, der Text auch im Menü des Fotos-Tabs (Blatt). Dateien: im Hauptordner keine Brotkrumen (der Titel sagt es), kürzere leere Zustände. Koppel-Blatt: ein Satz, "Link statt QR-Code einfügen" zugeklappt solange die Kamera geht. Import-Blatt: "Gut zu wissen" zugeklappt.

Schnellaktionen am App-Symbol (langes Drücken, `UIApplicationShortcutItems` in `project.yml`, Typen `com.onlyus.heimherz.aktion.codes|fotos|passwort`): "Codes" (Passwörter, Liste Codes), "Fotos sichern" (Fotos-Tab, startet den Abgleich wie der Knopf, nur mit voller Fotos-Erlaubnis), "Neues Passwort" (Formular). `HeimherzAppDelegate.application(_:configurationForConnecting:options:)` legt beim Kaltstart `options.shortcutItem` ins Postfach `SchnellaktionPostfach` (`App/Schnellaktion.swift`, wie `ImportPostfach`) und setzt `HeimherzSzenenDelegate` als Szenen-Delegate; der nimmt im Warmstart `windowScene(_:performActionFor:)` an. Der Kaltstart läuft nur über die Verbindungsoptionen, der Warmstart nur über den Szenen-Delegate, nie beides. `AppRootView` wechselt den Tab sofort; das Ziel (`PasswoerterInhalt`, `FotosInhalt`) führt aus, sobald nicht gesperrt (und bei Passwörtern der Tresor offen) ist, und nimmt die Aktion dabei aus dem Postfach (einmal). Ungekoppelt oder ohne Erlaubnis wird sie verworfen. Debug: `-heimherzAktion codes|fotos|passwort`.

## 9. Modul `ios-passwoerter`

Liste mit Suche (Name, Benutzer, Host), Favoriten oben. Detail: Benutzer und Passwort kopieren (Zwischenablage `localOnly`, Ablauf 60 s), Passwort zeigen nach Face ID, TOTP-Code mit Ring. Neu und Bearbeiten, Löschen als Grabstein. Generator (Länge 8 bis 64, Ziffern, Zeichen, Wortgruppen-Modus). Abgleich: beim Öffnen, nach jeder Änderung, per Ziehen; Ablauf `GET` → entschlüsseln → zusammenführen → verschlüsseln → `PUT If-Match`; 409 = nochmal (höchstens 3). Nach jedem Abgleich Identitäten an `ASCredentialIdentityStore` geben (nur Host, Benutzer, id). App sperrt nach 5 min im Hintergrund.

### Passwörter wie die Apple-App (T10)

Startseite mit Kacheln Alle, Favoriten (nur wenn es welche gibt), Passkeys, Codes, Sicherheit, Gelöscht (Zahlen live aus dem Tresor, genau so viele Zeilen hat die Liste). Listen mit A bis Z Leiste (eigene `AlphabetLeiste`), Sortierung Name oder Zuletzt geändert, "Auswählen" mit Mehrfach-Löschen (ein Speichern, ein Abgleich, Rückfrage), Suche unten, Plus. Codes: alle Einträge mit lesbarem TOTP, Code groß mit Ring und Restzeit, Tippen kopiert (Zwischenablage wie sonst), verdeckt bis Face ID (einmal je Öffnen der App, `TresorStore.codesFreigegeben`, `sperren()` setzt zurück). Passkeys (`bitwardenFido2` und `passkeys`): nur Anzeige, Anmelden damit kommt später. Sicherheit lokal ohne Netz (`PasswortSicherheit`): "Bereits verwendetes Passwort" und "Schwaches Passwort" (kurz, Reihen, Wiederholungen, häufige Wörter; ab 16 Zeichen nie nur wegen Kürze), Datenlecks nur mit eingeschalteter Einstellung (Runde 3, unten). Gelöscht: 30 Tage mit Wiederherstellen und Endgültig löschen. Symbole der Seiten über `GET /v1/symbol` (App-Gruppen-Cache, graue Buchstaben-Kachel sofort, Symbol lädt nach, nur sichtbare Zeilen). Import aus Apple Passwörter per Credential Exchange (iOS 26): `ImportPostfach` nimmt die `NSUserActivity` `ASCredentialExchangeActivity` an, `ASCredentialImportManager.importCredentials(token:)` liefert die Daten, `CredentialImportAdapter` übersetzt, `ImportAbbildung.einarbeiten` mischt ein (gleicher Host, Benutzer und Passwort: überspringen; gleicher Host und Benutzer, anderes Passwort: aktualisieren, altes in `passwortVerlauf`; Passkeys als unbekanntes Feld `passkeys` mit Schlüssel im verschlüsselten Tresor; WLAN, Karten und Sonstiges übersprungen), danach sofort Abgleich. Info.plist: `SupportsCredentialExchange` und `SupportedCredentialExchangeVersions [1.0]` im Block der Erweiterung, `NSUserActivityTypes` in der App. Ob iOS Heim in der Exportliste anbietet, zeigt erst das Gerät.

### Runde 3 (T15, W-012, W-014 bis W-017, W-020, W-021)

- **Codes (W-014):** Tippen in der Liste kopiert den Code (`localOnly`, Ablauf 60 s, Haptik, Hinweis "Code kopiert"). In den letzten 5 s eines Codes (Periode über 5 s) steht der nächste klein darunter ("Danach 123 456"), Tippen kopiert dann gleich den nächsten (`PasswoerterLogik.codeZumKopieren`, entschieden im Moment des Tippens, Hinweis "Nächster Code kopiert").
- **Passwort ändern (W-015):** "Passwort ändern …" im Menü des Details, unter dem Sicherheitshinweis im Detail und als Wisch/Kontextmenü in Sicherheit. Öffnet `https://<host>/.well-known/change-password` im Standardbrowser (`openURL`); nur für lebendige Logins mit Host.
- **Datenlecks (W-016), Ausnahme von Abschnitt 19 "Nie Daten an Dritte":** nur mit `GeteilteEinstellungen().leckPruefung` (Standard an, Ahmeds Auftrag 25.10.). `LeckPruefung`/`LeckAbfrage`: Pwned Passwords Range API (`GET https://api.pwnedpasswords.com/range/<5 Zeichen SHA-1>`, Header `Add-Padding: true`, Füllzeilen mit Anzahl 0 zählen nicht, kein Token, eigene Sitzung ohne Cache, 10 s). Nur diese 5 Zeichen verlassen das Handy, der Vergleich der Suffixe läuft lokal. Höchstens alle 24 h für alle Einträge, dazwischen nur neue oder geänderte (Stand je id: `geaendert`). Gespeichert wird je Eintrags-id nur `{geaendert, gefunden}` plus der Zeitpunkt des letzten vollständigen Laufs (App Group, `LeckSpeicher`), nie Hash oder Passwort. Jeder Fehler (kein Netz, Status außer 200, Abbruch) ändert nichts und rückt den Tagesstempel nicht vor. Sicherheit zeigt "In Datenlecks gefunden" ganz oben (`SicherheitsGrund.datenleck`, wichtigster Grund), die Kachel zählt diese Einträge mit (`TresorStore.leckIds`, ein gespeicherter, beobachteter Wert). Einstellung aus: keine Abfrage, kein Abschnitt, keine Zählung. Entkoppeln: `LeckSpeicher().vergiss()`.
- **Frühere Passwörter (W-017):** im Detail eine Zeile "Frühere Passwörter (N)" (nur wenn N > 0) mit Unterseite `FruehereSeite`. Quellen `passwortVerlauf` (`[{passwort, bis}]`) und `bitwardenVerlauf` (`[{password, lastUsedDate}]`), ohne Doppelte und ohne das aktuelle Passwort, neueste zuerst. Anzeigen und Kopieren nur nach Face ID (`GeraeteAbfrage`), Anzeige schließt nach 30 s und beim Verlassen.
- **Zuletzt benutzt (W-020):** Sortierung "Zuletzt benutzt" nur in "Alle" (im Sortieren-Knopf); Quelle `Nutzung().zuletzt`, nie benutzte danach nach Name. Kopieren in der App (Detail, Codes, frühere Passwörter) ruft `Nutzung().merke(id:)`.
- **Doppelte Konten (W-021):** `DoppelteKonten.finde`: gleicher Host (ohne `www.`) und gleicher Benutzer (ohne Groß- und Kleinschreibung, nicht leer), nur lebendige Logins; Einträge mit mehreren Hosts wachsen zu einer Gruppe zusammen. In Sicherheit der Abschnitt "Doppelt" (nicht in der Kachelzahl); Tippen öffnet `VergleichBlatt` (Passwörter nur als "gleich/unterschiedlich", nie im Klartext). Löschen nur einzeln mit Rückfrage als Grabstein; nie automatisch zusammenführen.
- **Spotlight (W-012):** `SpotlightIndex` (CoreSpotlight, eigener Index `heimherz`, Schutzklasse `.complete`, Bereich `com.onlyus.heimherz.konten`) mit Titel und Host lebendiger Logins; kein Benutzer, Passwort, Notiz, Code, keine Notizen-Einträge. Neu aufgebaut nach jedem Abgleich und jeder Änderung (`TresorStore.tresorStandGeaendert`, gleiche Kette wie die AutoFill-Identitäten), nie beim Sperren; `SpotlightIndex.leeren()` beim Entkoppeln. Tippen in der iPhone-Suche: `.heimherzSpotlightAnnahme()` legt die Eintrags-id in `SpotlightPostfach` (wie `ImportPostfach`), die Passwörter-Ansicht holt sie ab, sobald der Tresor offen ist (5 min Wartezeit, unbekannte ids fallen weg).
- **Neue 2FA-Codes in Heimcloud (W-028, Runde 4):** ein Link oder QR-Code zum Einrichten landet direkt im Tresor, nicht im Authenticator. Ahmed 25.10.: in iOS unter Einstellungen > Allgemein > AutoFill & Passwörter steht ganz unten „Codes konfigurieren in: Authenticator“ („… wird verwendet, um Links und QR-Codes zum Einrichten von Bestätigungscodes zu öffnen“).
  - **Belegt (Quellen):**
    - Apples Doku „Providing one-time passcodes to AutoFill“ (developer.apple.com/documentation/authenticationservices/providing-one-time-passcodes-to-autofill) beschreibt nur das Ausfüllen von Codes (`ProvidesOneTimeCodes`, steht seit T8 in der Erweiterung). Vom Einrichten neuer Codes steht dort nichts, ebenso wenig in der Seite zu `ASCredentialProviderViewController`.
    - Apple-Entwicklerforum, Thread 711392 (Aug 2022, iOS 16 Beta): ein Apple-Mitarbeiter schreibt „An app will appear in this list if it registers itself as a handler of the `otpauth` URL scheme.“ Das ist ein Forenbeitrag, keine Dokumentation.
    - Thread 711933: derselbe Abschnitt verschwand in späteren Betas, Apple hat nie geantwortet.
    - Bitwarden-Hilfe („Set as default on iOS“, iOS 16+) und Dashlane nennen die Einstellung „Set Up Codes In“ unter Verification Codes; ein Eintrag dort öffnet Links und QR-Codes zum Einrichten in der gewählten App.
    - Der Text auf Ahmeds Gerät („Links und QR-Codes … öffnen“) passt zu einer Übergabe als URL.
  - **Nicht belegt, nur am Gerät beweisbar:** ob iOS 26 Heimcloud mit dem Schema `otpauth` in dieser Liste anbietet (die Regel stammt aus iOS 16); ob außer dem Schema noch etwas nötig ist (die Heim-Erweiterung ist ohnehin Anbieter für Passwörter und Codes); ob die Kamera und Safari den Link wirklich an Heimcloud geben; dass der Link als `onOpenURL` ankommt (angenommen, so wie jede URL).
  - **Gebaut:**
    - Einziger Mechanismus ist das URL-Schema: `project.yml` (App-Ziel) `CFBundleURLTypes` mit `otpauth`. `onOpenURL` nimmt nur dieses Schema an (`CodePostfach.istCodeLink`), alles andere wird ignoriert.
    - Strenger Parser `OtpAuth.lese` (`Gemeinsam/Tresor/OtpAuth.swift`, Key URI Format): `secret` in Base32, `issuer`, Label `Anbieter:Konto` (der Parameter `issuer` gewinnt), `algorithm` SHA1/SHA256/SHA512, `digits` 6 oder 8, `period` 1 bis 3600 (Standard 30), höchstens 2048 Zeichen. Fehler sind `OtpFehler` mit deutschem Text, nie mit dem Geheimnis darin. HOTP wird mit eigenem Hinweis abgelehnt. `TOTP.einstellung(aus:)` bleibt die nachsichtige Fassung für gespeicherte Werte.
    - Im Tresor steht der Link in fester Form (`OtpAuth.uri`: Base32 ohne Füllzeichen, Namen prozentkodiert, immer mit `algorithm`, `digits`, `period`), damit SHA256, 8 Stellen und die Periode nicht verloren gehen. Tresorformat unverändert.
    - `CodePostfach` (wie `ImportPostfach`): nur im Speicher, 300 s Wartezeit, wird genau einmal herausgegeben. Das Blatt erscheint erst, wenn `TresorStore.zustand == .bereit` und nicht gesperrt: der Store lädt K mit dem Kontext der Sperre, darum gilt Face ID beziehungsweise das Entsperr-Fenster (`entsperrDauer`) ohne zusätzliche Abfrage. Sperren oder Entkoppeln schließt das Blatt und verwirft den Code. Ohne Kopplung kommt eine Meldung.
    - Blatt „Code einrichten“ (`CodeEinrichtenBlatt`): Anbieter und Konto oben, darunter Vorschläge (`CodeZuordnung.vorschlaege`: Anbieter muss passen, als Domain über `EintragSuche.passt`, sonst gleicher Name oder Host-Teil, Teiltreffer erst ab 3 Zeichen; gleicher Benutzer sortiert nach oben und reicht nur allein, wenn der Link keinen Anbieter nennt), „Anderes Konto wählen“ mit Suche, „Neuer Eintrag“ (Name = Anbieter, Benutzer = Konto, ohne Webseite). Hat der Eintrag schon einen anderen Code: Rückfrage, der alte Schlüssel wandert in das unbekannte Feld `totpVerlauf` (`[{totp, bis}]`, neueste zuerst, höchstens 5). Danach der laufende Code mit Ring und „Kopieren“ (`Zwischenablage`, nur dieses Gerät, 60 s).
    - Speichern wie jede Änderung über `TresorStore.speichere`: lokal verschlüsselt, Abgleich mit dem PC, AutoFill-Identitäten neu (`Gemeinsam/AutoFill` unverändert). Das Blatt prüft nach dem Speichern, ob der Code wirklich im Tresor steht; sonst Fehlertext statt Erfolg.
    - Das Geheimnis steht nie in Logs, Spotlight, Zwischenablage (nur der Code) oder UserDefaults.
    - Formular „Bearbeiten/Neu“: Feld „Einrichtungsschlüssel oder otpauth://-Link“ (tippen oder einfügen) und „QR-Code scannen“ (`QRScanner`, nur mit Kamera); Anbieter und Konto füllen leere Felder Name und Benutzer. Ein geänderter oder geleerter Schlüssel kommt auch hier in `totpVerlauf` (`Entwurf.anwenden`).
    - Einstellungen > Passwörter: Zeile „Neue 2FA-Codes in Heimcloud“ mit Unterseite (`CodesAnleitung`): oben „QR-Code scannen“ und der Link-Weg (geht immer), darunter die drei Schritte in iOS, als „sollen“ formuliert, mit dem Satz, dass erst das Handy zeigt, ob iOS Heimcloud anbietet.
    - `NSCameraUsageDescription` nennt jetzt auch die QR-Codes für Einmalcodes und „Heimcloud“.
  - **Nicht gebaut:** `otpauth-migration://` (Export aus Google Authenticator): braucht einen handgeschriebenen Protobuf-Leser an einer Vertrauensgrenze und eine Auswahl für mehrere Konten, passt nicht zum Blatt für ein Konto. Das Schema ist nicht eingetragen; ein gescannter Export zeigt „Richte den Code bei der Seite noch einmal ein“. Auch nicht gebaut: HOTP, Steam-Codes, Anzeige von `totpVerlauf` in der App (der alte Schlüssel liegt im Tresor und im Verlauf am PC), automatisches Kopieren des neuen Codes.
  - Geprüft in CI: Parser (RFC-6238-Werte, Google-Beispiel, Randfälle), Zuordnung, Verlauf, Postfach, Speichern über den Store inklusive Identitäten; Screenshots `code-auswahl`, `code-ersetzen`, `code-fertig`, `einstellungen-codes` (hell und dunkel). Nur am Gerät: Heimcloud in „Codes konfigurieren in“, Ankunft des Links aus Safari und Kamera, Face ID beim Kaltstart über den Link.
- Geprüft nur in CI: Logik und Store mit Attrappen. Nur am Gerät: Safari öffnet die Adresse, Face-ID-Abfragen, echter Aufruf bei Pwned Passwords, Spotlight-Treffer und Tipp, Ablauf der Zwischenablage nach 60 s.

### Gebaut (T5, Abweichungen und Festlegungen)

- Dateien: `Heimherz/Sources/Module/Passwoerter/` (`TresorStore` = Klartext nur im Speicher, `PasswoerterTabView`, `EintragDetailView`, `EintragFormular`, `GeneratorBlatt`, `Entwurf`, `Hilfen`), geteilt in `Gemeinsam/AutoFill/` (`EintragSuche`, `AutoFillIdentitaeten`, `PasswortGenerator`, `Wortliste`).
- Sperren: Der Store leert Tresor und Schlüssel, sobald die App sperrt oder entkoppelt wird; Ergebnisse von Aufgaben, die vor der Sperre starteten, werden verworfen (`sperrZaehler`).
- Änderungen werden erst lokal verschlüsselt gespeichert (`speichereLokal`), dann abgeglichen; Abgleich beim Öffnen, nach jeder Änderung, beim Zurückkehren in die App und per Ziehen. "Zuletzt abgeglichen" bleibt über Neustarts (UserDefaults, nur die Zeit).
- Passwort zeigen: Geräteabfrage (`LAContext` `.deviceOwnerAuthentication`), danach 30 s sichtbar. Kopieren: `UIPasteboard` mit `localOnly` und Ablauf 60 s.
- Generator: Zeichen-Modus (8 bis 64, Ziffern, Sonderzeichen `!#$%&*+-=?@_`, von jeder Klasse mindestens eins), Wortgruppen-Modus (3 bis 8 Wörter, optional Zahl, Trenner). Wortliste (1180 Wörter, kleingeschrieben, ASCII) steht im Quelltext (`Wortliste.swift`) statt als Bundle-Ressource, weil die AutoFill-Erweiterung dasselbe Modul `Gemeinsam` nutzt und kein Zugriff auf das App-Bundle hat. Zufall: `SystemRandomNumberGenerator`.
- Identitäten (`AutoFillIdentitaeten.baue`): je lebendigem Login mit Benutzer und je Host der URLs eine `ASPasswordCredentialIdentity` (`.domain`, `recordIdentifier` = Eintrag-id, `rank` 1 bei Favorit); bei lesbarem TOTP zusätzlich eine `ASOneTimeCodeCredentialIdentity`. Nie Passwort oder TOTP-Geheimnis.
- Hostzuordnung: gleicher Host oder Unterdomain an der Punktgrenze (`m.example.com` passt zu `example.com`, `evilexample.com` nicht). Keine Public-Suffix-Liste (`shortcut:` im Code).

Gebaut (25.10., Prüfung): `TresorDienst.speichereLokal` liest die Datei direkt vorher neu und führt sie ein (App und Erweiterung überschreiben sich nie); auch der Abgleich schreibt keinen Stand über Änderungen, die währenddessen in die Datei kamen. `TresorAblage` merkt in `tresor.abgeglichen`, wann der PC zuletzt bestätigt hat (Grundlage für "N Änderungen noch nicht am PC"). Passphrase standardmäßig 6 Wörter.

## 10. Modul `ios-autofill`

`ASCredentialProviderViewController`:
- Passwort: `prepareCredentialList(for:)` mit Liste passend zur Domain, `provideCredentialWithoutUserInteraction` nur wenn K ohne Abfrage lesbar ist, sonst `ASExtensionError.userInteractionRequired`.
- Einmalcode (ab iOS 18): `ASOneTimeCodeCredentialIdentity` für Einträge mit TOTP.
- Speichern und Generieren (ab iOS 26.2, API-Namen vor dem Bau in Apple-Doku prüfen): neuer Eintrag landet im Cache und wird beim nächsten App-Start abgeglichen (Erweiterung macht kurz selbst `PUT`, wenn der PC erreichbar ist).
- Neue Codes einrichten (W-028) braucht die Erweiterung nicht: der Link kommt in der App an (`otpauth` in `CFBundleURLTypes` des App-Ziels, Abschnitt 9). `ProvidesOneTimeCodes` bleibt, damit iOS die fertigen Codes ausfüllt; die Identitäten der neuen Codes setzt der Store wie bei jeder Änderung.
- Info.plist: `ASCredentialProviderExtensionCapabilities` mit `ProvidesPasswords`, `ProvidesOneTimeCodes`, `SupportsCredentialExchange` (für späteren iCloud-Import).
- Speichergrenze der Erweiterung beachten (kein großes Laden, Tresor nur einmal entschlüsseln).

### Gebaut (T8, Abweichungen und Festlegungen)

- Dateien: `HeimherzAutoFill/Sources/` (`CredentialProviderViewController` übersetzt nur zwischen System und Modell, `AutoFillAnsichten` = SwiftUI aus `Gemeinsam/Design`), Ablauf testbar in `Gemeinsam/AutoFill/` (`AutoFillSitzung`, `AutoFillModell`, `PasswortSpeichern`, `PasswortVorschlaege`).
- `performWithoutUserInteractionIfPossible(savePasswordRequest:)` meldet immer `userInteractionRequired` (Speichern braucht den Schlüssel und eine Rückfrage). `provideCredentialWithoutUserInteraction` liefert seit W-009 Passwort und Einmalcode direkt aus der Vorschlagsleiste, ganz ohne Blatt, wenn das Entsperr-Fenster offen ist (Abschnitt 2) und der Host der gewählten Identität zu einem Host des Kontos passt (`EintragSuche.passt`, Punktgrenze; Grabstein, Notiz, `.app`-Bezeichner ohne Host: nein). In jedem anderen Fall `userInteractionRequired`, dann zeigt iOS das Blatt (`prepareInterfaceToProvideCredential`, ein Face ID).
- Schneller (W-010): Face ID startet von selbst; die Oberfläche meldet `ansichtIstAktiv()` erst, wenn der Auftrag gesetzt und `viewDidAppear` da war (Rückfall nach 2 s). Ursache des "-25308" (`errSecInteractionNotAllowed`) war nach Lage des Codes, dass `.task` der SwiftUI-Ansicht beim ersten Erscheinen lief, bevor iOS die Abfrage der Erweiterung zuließ (am Gerät nicht belegt). Bleibt es dennoch, holt das Modell es bis zu 3-mal nach (je 300 ms), danach erscheint der Knopf "Entsperren" ohne Fehlertext; die Nummer sieht Ahmed nie. Kein Abgleich mit dem PC vor dem Ausfüllen (nur der lokale verschlüsselte Cache).
- Code nach dem Login (W-011): Jeder Login mit lesbarem TOTP hat je Host eine `ASOneTimeCodeCredentialIdentity` (iOS bietet im Codefeld "Code aus Heim" an, im Fenster ohne Blatt). Zusätzlich liegt nach dem Ausfüllen eines Passworts auf passendem Host der aktuelle Code in der Zwischenablage (Einstellung `codeKopieren`, `localOnly`, Ablauf 60 s, nie nach einem Code oder einem fremden Konto). Nutzung (`Nutzung.merke`) wird bei jedem Ausfüllen gemerkt. Codes per SMS oder Mail kann nur iOS selbst vorschlagen ("Aus Nachrichten").
- Phishing-Schutz (25.10.): Ohne Blatt füllt Heim nur bei passendem Host (siehe oben). Wählt Ahmed in der Liste (Suche) ein Konto, das nicht zur Seite passt, fragt eine Karte "Dieses Konto gehört zu X, die Seite ist Y. Trotzdem ausfüllen?"; der Code geht dann nie in die Zwischenablage. Gefälschte Hosts wie `sparkasse.de.evil.com`, `evilsparkasse.de`, `sparkasse-de.com` passen nicht zu `sparkasse.de`. Warum Webseiten oder Skripte AutoFill nicht ohne Tippen auslösen können: iOS füllt nie beim Laden einer Seite, sondern nur nach einem Tippen in der Vorschlagsleiste, und nur in das fokussierte Formular der angezeigten Domain; versteckte Felder oder Skripte können weder die Erweiterung aufrufen noch das Ergebnis lesen, bevor Ahmed tippt. Das Ergebnis der Prüfung hier ist die zweite Verteidigungslinie. Die Anfrage-API nennt dem Ausfüllen ohne Blatt nur den Host der gewählten Identität, nicht die geladene Seite; die Seite prüft iOS selbst.
- Ein Face ID je Aufruf: ein `EntsperrKontext` je `AutoFillSitzung`, der Tresor wird einmal aus dem verschlüsselten Cache geöffnet und nur im Speicher gehalten.
- Speichern (iOS 26.2, belegt in der Apple-Doku): `performWithoutUserInteractionIfPossible(savePasswordRequest:)`, `prepareInterface(for: ASSavePasswordRequest)`, `completeSavePasswordRequest(completionHandler:)`; Info.plist `SupportsSavePasswordCredentials`. Bei `event == .userInitiated` und neuem Konto wird sofort gesichert, sonst fragt eine Karte "In Heimherz sichern?". Gleicher Benutzer und passender Host mit anderem Passwort fragt immer nach ("Passwort aktualisieren?"). Gleiches Passwort ist schon da: nichts tun. Lokal verschlüsselt speichern, dann höchstens 6 s mit dem PC abgleichen, danach Identitäten setzen.
- Passwort-Vorschläge (iOS 26.2): `performWithoutUserInteraction(generatePasswordsRequest:)`, `completeGeneratePasswordRequest(results:completionHandler:)`, `ASGeneratedPassword(kind:value:)` mit `.strong`, `.alphanumeric`, `.passphrase`; Info.plist `SupportsGeneratePasswordCredentials` und `SupportsGeneratePasswordCredentialsWithUI` = false (keine eigene Oberfläche, das System zeigt die Auswahl). Es werden nur `minlength` und `maxlength` der Seitenregeln beachtet (`shortcut:` im Code); Vorschläge, die länger als `maxlength` wären, entfallen.
- Einstellungen: `ShowsConfigurationUI` = true, `prepareInterfaceForExtensionConfiguration` zeigt einen kurzen Hinweis, `completeExtensionConfigurationRequest()` schließt.
- `SupportsCredentialExchange` ist seit T10 gesetzt (nur Import aus Apple Passwörter, Annahme in der App, siehe Abschnitt 9); ein Export aus Heim ist nicht gebaut.
- Die Passwörter-App mischt vor jedem Schreiben und Abgleichen den Cache-Stand ein, falls die Erweiterung zwischendurch gespeichert hat. Ein gleichzeitiges Schreiben beider Prozesse im selben Augenblick ist nicht abgesichert (kleines Fenster, der Merge holt es beim nächsten Abgleich nach, solange der Eintrag in einer der beiden Fassungen steht).

Gebaut (25.10., Prüfung): genauer Host-Treffer geht vor Unterdomain-Treffer (Liste und Speichern); beim Aktualisieren zeigt der Dialog alle Hosts des Eintrags und warnt, wenn die Seite nur eine Unterdomain davon ist. Das ersetzte Passwort bleibt als `passwortVerlauf` (unbekanntes Feld, Liste `{passwort, bis}`, neueste zuerst, höchstens 5) am Eintrag. Das sichtbare Passwort in der Detailansicht ist nicht auswählbar (Kopieren nur über den Knopf, `localOnly` mit Ablauf).

## 11. Modul `ios-fotos`

- Erlaubnis Fotos (voller Zugriff). Abgleich: alle `PHAsset`, deren Kennung nicht in `GET /v1/fotos/bekannt` steht; je Ressource (`PHAssetResource`: Foto, gepaartes Video, Video, bearbeitete Fassung nicht) Export per `PHAssetResourceManager.writeData` in eine Temp-Datei, dann Hintergrund-`URLSession` `uploadTask(fromFile:)`. Kennung = SHA-256 von `localIdentifier`, b64url, 43 Zeichen.
- Erweiterung `HeimherzFotos`: `PHBackgroundResourceUploadExtension` (iOS 26.1), erzeugt `PHAssetResourceUploadJob` mit `URLRequest` auf `PUT /v1/fotos/…`. Ein- und Ausschalten in der App. Simulator geht nicht, nur am Gerät.
- Anzeige: Fotos gesamt, am PC, offen, letzte Übertragung, Fehler in Klartext. Nur WLAN als Schalter (Standard an, Videos immer nur WLAN).
- Nie etwas in der Mediathek löschen oder ändern.

Gebaut (25.10.): Server antwortet auf `OPTIONS /v1/fotos/…` ohne Token mit 501 (kein Resumable Upload, Apple-Weg) und nimmt POST wie PUT; Teil-Uploads 400. Ressourcen `foto-N`, `video-N`, `live-N`, `alternative-N`, `ton-N`; bearbeitete Fassungen gehen nicht mit (später). `Gemeinsam/Fotos/` teilt Kennung, Plan und Stand (`fotos-stand.json` in der App Group) zwischen App und Erweiterung; die Erweiterung hat kein Netz zum Abfragen und liest `bekannt` aus dem Stand. Vor iOS 26.5 merkt sie eingereichte Jobs selbst (3 Tage), vor 26.4 kein `job.error`. Ohne WLAN wartet die App statt iCloud-Originale mobil zu laden. Runde 2 (W-003, 25.10.): Abgleich nur per Knopf "Abgleich starten"/"Anhalten", neueste zuerst, Stücke zu 20 Dateien, Stand dauerhaft in `fotos-stand.json`; Anhalten bricht laufenden Upload und Export ab (`requestData`/`cancelDataRequest`), fertige Dateien zählen. Der Tab zählt beim Öffnen nur, startet nicht. `BGContinuedProcessingTask` (`com.onlyus.heimherz.fotos-abgleich`) trägt einen gestarteten Lauf, `BGProcessingTask` (`.fotos-nacht`) nachts mit Strom, solange etwas offen ist. `handleEventsForBackgroundURLSession` über `HeimherzAppDelegate`. Raster "Fotos sehen" mit Filter Alle / Am PC / Noch nicht und Status je Bild, Einzelbild mit "Jetzt hochladen" (gesperrt während eines Laufs). Schalter "Originale aus iCloud laden". "Anhalten" stoppt nicht die Foto-Erweiterung (eigener Schalter).

Runde 3 (W-007, W-018): Die Schalter (nur WLAN, Originale aus iCloud, Im Hintergrund hochladen) und "Wie das Sichern läuft" wohnen in den Einstellungen (Abschnitt "Einstellungen"); das Verhalten ist unverändert. "Videos nur WLAN" ist eine feste Regel und steht als Fußzeile dort, kein Schalter. Mitteilung "N Fotos gesichert" (`FotoMitteilung`, `MitteilungsDienst`): `FotosModell.laufBeendet` meldet, wenn der Lauf per Knopf oder als Nachtlauf lief (`plantNachts`), der Nutzer nicht angehalten hat, `GeteilteEinstellungen.fotoMitteilung` an ist und `FotoAnzeige.gesichert` größer 0 ist. `gesichert` zählt im `FotoAbgleich` die Fotos, die in diesem Lauf vollständig am PC ankamen (nicht die Zunahme von `amPC`, nicht Dateien: ein Live Photo zählt einmal). Zählen und Einzel-Upload melden nie. Die Erlaubnis fragt der erste Start per Knopf und das Einschalten des Schalters (nur wenn iOS noch nie gefragt hat). Steht die App im Vordergrund, zeigt iOS die Mitteilung nicht (der Lauf ist dort zu sehen).

Tempo (Runde 3, Messung am Gerät: nacheinander 2,6 MB/s, "ca. 7 Std. 52 Min." für 6.995 Dateien, PC am Kabel und direkt im LAN, also kein Netz- oder Serverproblem): `FotoAbgleich` lädt mehrere Dateien zugleich hoch, 6 im WLAN und 2 mobil (`wlanParallel`, `mobilParallel`, vor jedem Stück neu gewählt), und exportiert im Voraus: bis zu 12 fertige Dateien (`standardVoraus`) und höchstens 1 GB (`standardPuffer`) warten auf einen freien Platz (`UploadSchranke`). Temp-Dateien also höchstens 6 + 12. Zwei Durchgänge: erst alles, was lokal liegt (Export mit `isNetworkAccessAllowed = false`, scheitert er, wird die Datei zurückgestellt), dann die iCloud-Originale (nur mit "Originale aus iCloud laden"), dabei höchstens 2 Downloads zugleich. Stücke zu 60 Dateien. `HintergrundUpload` nimmt im Vordergrund eine normale `URLSession` (iOS drosselt die Hintergrund-Sitzung) und fällt auf die Hintergrund-Sitzung zurück, wenn die App schlafen geht (Netzfehler, App nicht mehr aktiv) oder nachts; beide laden direkt aus der Datei (`upload(for:fromFile:)`, `uploadTask(with:fromFile:)`). Läuft ein Abgleich im Vordergrund und das Handy hängt am Strom, bleibt der Bildschirm an (`BildschirmWach`, `isIdleTimerDisabled`), im Hero steht "Bildschirm bleibt an, solange am Strom". Reihenfolge: erst alle Fotos (`PHAssetMediaType.image`, ein Live Photo gehört als Ganzes dazu), dann alle Videos, in beiden Gruppen neueste zuerst (`FotoPlan.plane` sortiert die Köpfe stabil nach `FotoKopf.istVideo`; der Medientyp ist die Näherung für "klein vor groß", die Dateigröße gäbe es nur über einen privaten Schlüssel). Mit den zwei Durchgängen: lokal Fotos, lokal Videos, iCloud Fotos, iCloud Videos. Der Hero zeigt "Fotos: 4.812 von 6.900 · danach 625 Videos" (`FotoPhasen`, `FotoText.phasen`). Jede Datei steht je Stück genau einmal in der Liste (kein 409 durch Doppelte), "neueste zuerst" gilt für den Start der Dateien, abgeschlossen wird in der Reihenfolge, wie sie fertig werden.

Tempo Runde 4 (T16): Messen statt raten. Jeder Upload meldet Zahlen an den PC (SPEC 6, `FotoMessung` setzt `X-Heim-Export-Ms`, `-Warte-Ms`, `-Aktiv`, `-Exporte`, `-Durchgang`; `HintergrundUpload` ergänzt `-Vordergrund` und `-Session` und rechnet den Sprung auf den Hauptthread in `-Warte-Ms` ein), `heimherz tempo` liest sie am PC. Die Anzeige zählt nur Dateien, die der PC mit 2xx bestätigt hat, und rechnet gleitend über die letzten 15 s (`FotoTempo.fenster`); die Restzeit ist offene Assets mal mittlere Größe je bestätigter Datei durch diese Geschwindigkeit. Ein Takt alle 2 s rechnet neu, auch wenn gerade nichts fertig wird (nach 15 s ohne bestätigte Bytes verschwindet die Zahl, statt "0" zu zeigen). Unter dem Tempo steht, solange ein Lauf aktiv ist, "Schneller, wenn Heimcloud offen bleibt." (`FotoText.vordergrundHinweis`, kein Dialog). Befunde und Änderungen: `HTTP/2` läuft über `tailscale serve` (geprüft: `curl --http2` = Version 2), dann teilen sich alle Uploads eine TCP-Verbindung und `httpMaximumConnectionsPerHost` wirkt nicht (Apple: "HTTP/2 and later run multiple requests over a single connection and thus ignore this property"). Der Export nimmt je Datei eine eigene `PHAssetResourceManager`-Instanz statt `default()` (Apple sagt nicht, ob eine Instanz Anfragen nacheinander abarbeitet). `isNetworkAccessAllowed` ist im lokalen Durchgang `false` (Apple: Standard `false`, ohne Netz schlägt der Rückruf mit Hinweis fehl). `alternative-N` und `ton-N` bleiben: es sind Originale (RAW-Gegenstück, Ton), sie wegzulassen verlöre Daten. Durchgehende Pipeline (Runde 4): Die Stücke zu 60 sind nur noch die Planungsgröße. `FotoAbgleich.sendeDurchgang` füllt die Warteschlange nach (`fuelleNach`), sobald weniger als `gleichzeitig + voraus` Dateien auf ihren Start warten, also während Uploads laufen; vorher wartete die Schleife nach jedem Stück, bis alles leer war, und plante dann neu. Jede Datei steht je Durchgang genau einmal in der Warteschlange (`geplant`, auch gegen 409 am PC). `FotoQuelleLive` liest die Mediathek je Lauf einmal (`PlanSpeicher`: Köpfe mit SHA-256 und die Dateilisten), jedes weitere Planen kostet nur noch Schleifen im Speicher; vorher las jedes Stück alle rund 7.500 Assets neu und schlug die Dateiliste jedes übersprungenen (etwa iCloud-only) Assets erneut nach, das wuchs mit jedem Stück. Der Stand (`fotos-stand.json`) wird alle 20 bestätigten Dateien oder alle 10 s gesichert, nie als Sperre. Zahlen und Phasen der Anzeige kommen aus dem ersten Plan je Durchgang und werden danach vom Lauf selbst gezählt. Neue Aufnahmen während eines Laufs sieht erst der nächste Lauf.

Offen, nur mit den Messwerten zu entscheiden: mehrere Sitzungen für mehrere Verbindungen, Zahl der Parallelen, Fenster-Wechsel (siehe Bericht).

Prüfung (25.10.): Ein Serverfehler (5xx) oder eine Ablehnung (4xx außer 401) überspringt nur diese Datei (gezählt, Grund im Stand, beim nächsten Lauf wieder offen). Den Lauf halten nur 401, 507 (`HeimFehler.speicherVoll`, Platte am PC voll) und echte Verbindungsfehler an. 411 kann nicht vorkommen: Uploads laufen über `uploadTask(with:fromFile:)` (Länge aus der Datei). Nach dem Entkoppeln ist die Foto-Erweiterung aus; sie schaltet sich nur bei gekoppeltem Handy wieder ein. Bereits angelegte Jobs tragen das alte Token und scheitern am PC.

## 12. Modul `ios-dateien`

Ordnerliste, Vorschau mit QuickLook (Download in Cache, Range wird nicht gebraucht), Teilen (`ShareLink`), Hochladen aus Dateien-App (`fileImporter`) und Fotos, in den Papierkorb legen mit Rückfrage. Kein Offline-Spiegel.

Gebaut (25.10.): Datei antippen öffnet ein Blatt mit Ansehen, Teilen, Papierkorb; Papierkorb auch per Langdruck. Fotos-Auswahl lädt Dateien (nicht Data), Name `Foto JJJJ-MM-TT HH-MM-SS.ext`, bis 20 auf einmal.

Prüfung (25.10.): `dateiHochladen` sendet über `upload(for:fromFile:)`, die Länge ist damit gesetzt (der Dienst verlangt sie jetzt, sonst 411). 507 hält den Upload-Lauf an.

Neues Aussehen (W-031, 25.10.): wie Apples Dateien, Ansicht "Durchsuchen". Nur Systemkomponenten und Systemfarben, kein eigener Hintergrund, keine Karten (`DateienTabView.swift`, `DateienAnsichten.swift`).
- Navigation: `NavigationStack` mit einem Ordner je Stufe (`OrdnerZiel`, eigenes `DateienModell` je Ordner), großer Titel = Ordnername, Zurück-Pfeil des Systems (langes Drücken zeigt den Weg). Keine Brotkrumen.
- Ansichten (Menü `ellipsis.circle` oben rechts, `@AppStorage heimherzDateienAnsicht`): Symbole (Raster, adaptiv ab 104 pt Breite, also 3 Spalten auf 390 pt; Vorschau 100 pt, Name bis zwei Zeilen mittig, darunter Datum und Größe klein grau, Ordner blau mit "12 Objekte") und Liste (Vorschau 40 pt, Name, "Datum – Größe", Ordner mit Pfeil). Bei Dynamic Type ab AX1 zwei Spalten.
- Sortieren (`heimherzDateienSortierung`): Name, Datum, Größe, Art; ein neues Kriterium startet in seiner Richtung (Name und Art A bis Z, Datum und Größe das Größte zuerst), nochmal Tippen dreht um; Pfeil im Menü zeigt Kriterium und Richtung. Ordner stehen immer oben, Gleichstand entscheidet der Name (`DateiSortierung`).
- Suche: `.searchable` mit Bereichsleiste "Alle | <Ordnername>" (nur in Unterordnern), Entprellen 300 ms, ältere Anfragen werden abgebrochen (`DateienSucheModell`). Treffer als Liste mit Ordnerpfad grau darunter; Datei antippen öffnet sie, Ordner antippen baut den Stapel bis dorthin auf.
- Vorschaubilder: `VorschauLader` (nur sichtbare Zellen, höchstens 4 gleichzeitig, `NSCache` im Speicher, 404 wird in der Sitzung nicht wiederholt); bis das Bild da ist, das graue Dateisymbol. Nur Endungen, die der Dienst kann (`DateiAnzeige.hatVorschau`).
- Datei antippen: laden (mit Anzeige), dann die Systemvorschau (QuickLook, dort auch Teilen). Langdruck: Teilen (Systemblatt), Informationen (Art, Größe, Datum, Ort), In den Papierkorb (rot, mit Rückfrage); Wischen nach links: Papierkorb. Kein "Neuer Ordner", kein Umbenennen, kein Verschieben (der Dienst kann es nicht).
- Ziehen nach unten lädt neu; leerer Ordner "Ordner ist leer"; unten "805 Objekte, 3,2 GB verfügbar" (`frei` aus `GET /v1/status`).
- Debug für Screenshots (nur DEBUG): `-heimherzDateienAnsicht liste|symbole`, `-heimherzDateienSortierung datum-ab`, `-heimherzDateienSuche <Text>`, `-heimherzDateienOrdner <Pfad>`.

Runde 3 (W-007): Der Zwischenspeicher der Vorschauen (`VorschauCache`, `Caches/Heimherz/Dateien`) wird in den Einstellungen mit Größe angezeigt und mit Rückfrage geleert (`VorschauCache.groesse`, `leere`). Im Hauptordner entfallen die Brotkrumen.

## Einstellungen (W-008, Runde 3)

Tab "Einstellungen" (Symbol `gearshape.fill`, Typ `HeimherzTab.einstellungen`, Debug `-heimherzTab einstellungen`), `Module/Einstellungen/`. Gruppierte Liste (`insetGrouped`) wie die iOS-Einstellungen, Zeilen mit farbigen Symbolkacheln (`EinstellungsKachel`, `KachelTitel`, `heimherzEinstellungenListe` in `Design/Bausteine.swift`).

| Gruppe | Zeilen | Wirkung |
|---|---|---|
| (Hinweis) | Build-Ablauf ab Tag 75 | `BuildAblauf.hinweis` |
| PC | Kopf (verbunden ja/nein, Gerätename = Host, Hausherz-Stimmung), "Zuletzt abgeglichen" | Unterseite `PCEinstellungenSeite`: Server, Dienst, Tresor-Stand, Fotos am PC, Frei am PC, Neu prüfen, Mit anderem PC koppeln, Entkoppeln (Rückfrage wie vorher). Ungekoppelt: Kopf und der eine große Knopf "Mit PC koppeln" |
| Sicherheit | "Face ID gilt für" (Picker `EntsperrDauer`), "2FA-Code nach dem Ausfüllen kopieren" | schreibt `GeteilteEinstellungen.entsperrDauer` und `codeKopieren` in die App Group. Die Wirkung bauen App-Sperre und AutoFill (Arbeiter B); die Ansicht bindet nur an. Fußzeile "Solange füllt Heim ohne neue Abfrage aus." |
| Passwörter | AutoFill einschalten (Unterseite `AutoFillAnleitung`), "Aus Apple Passwörter holen" (Blatt `ImportAnleitungBlatt`), "Auf Datenlecks prüfen" | `leckPruefung` (Wirkung: Arbeiter C). Fußzeile: nur 5 Zeichen eines Hashs an haveibeenpwned.com |
| Fotos (nur gekoppelt) | Nur im WLAN senden, Originale aus iCloud laden, Im Hintergrund hochladen (aus ohne volle Erlaubnis), Mitteilung nach dem Abgleich, "Wie das Sichern läuft" (Unterseite) | `FotosModell.setzeNurWLAN`, `setzeICloudLaden`, `schalteHintergrund` (unverändert) und `fotoMitteilung`. Die Fußzeile nennt, was gerade einen Schalter wirkungslos macht, sonst die Regel für Videos |
| Dateien (nur gekoppelt) | Zwischenspeicher am Handy (Größe, Leeren mit Rückfrage) | `VorschauCache.groesse`, `leere` |
| Über | Version, Build vom, TestFlight läuft ab in N Tagen | `BuildAblauf` |

Geteilte Werte liegen als `@State`-Kopie in der Ansicht und werden mit `.onChange` in die App Group geschrieben (UserDefaults melden Änderungen nicht an SwiftUI). "Zuletzt abgeglichen" liest den Merker des `TresorStore` (`TresorStore.merkerSchluessel`). Debug: `-heimherzEinstellungenSeite pc|autofill|sichern`.

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
- Nie: Daten an Dritte (einzige Ausnahme: Leck-Prüfung schickt 5 Zeichen eines SHA-1 an api.pwnedpasswords.com, abschaltbar, SPEC 9), Dienst ins offene Internet (Funnel, Cloudflare), eigene Krypto-Primitive (nur CryptoKit und WebCrypto), Kauf von Speicher, echte Tresordaten in Tests oder Fixtures.

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

## 23. Modul `agenten-fuellen` (W-006, 25.10.2026)

Ahmed 25.10.: "wir wollen anhand von stärke des models und Auftrag bestimmte erlaubnis kategorien für heim herz auf pc. Agenten sollen sehr schnell seamless fill in machen können und confirmation code auch rein fillen." Und: "Sparkasse ist das sensibelste was wir haben. Da drunter kommt kündigen. Dann an amt schicken." "Wenn dann mein Auftrag Datei explizit sagt geh in sparkasse melde dich an und mach was bitte ich bin nicht zuhause und mach alles alleine. Dann darf er. Sonst dürfen die mein sparkasse nicht anfassen."

### Bekannte Probleme, die das löst
- Kein Agent-Weg: Agenten füllen weiter mit `claude-bw fuell` (5,7 s je Aufruf, `bw` startet jedes Mal; Heimherz 1,2 s).
- Doppelte und falsche Einträge (Kausar: zwei Arbeitsagentur-Einträge, TOTP nur in einem; Apple dreimal): Agent nimmt den falschen. Auswahl: passender Host, dann `--konto`, dann der Eintrag, der den gesuchten Wert hat (Code = mit TOTP).
- Keine Stufen: jeder Agent konnte jeden Login füllen, auch die Sparkasse.
- Neue Logins der Bitwarden-Wache kommen nur per `heimherz import bitwarden` an (Phase 2).

### Befehle
- `heimherz fuell TAB CSS benutzer|passwort|code [--konto K] [--rahmen IFRAME-CSS] [--enter] [--auftrag DATEI]`: gleicher Vertrag wie `claude-bw fuell`. TAB muss in den eigenen `claude-chrome`-Fenstern liegen (`claude-chrome tabs`) und https sein; nur Einträge, deren Host zur Seite passt (gleicher Host oder Unterdomain derselben Seite). Wert geht nur per CDP `Input.insertText` (`127.0.0.1:9333`) ins Feld, nie in stdout, argv, Log. Ausgabe: `ok: passwort (benutzer) N Zeichen in HOST`. `code` = TOTP (RFC 6238, SHA1/256/512, 6 oder 8 Stellen, Periode aus otpauth), lokal berechnet; ist der Code in weniger als 3 s ungültig, auf den nächsten warten.
- `heimherz totp-setzen TAB --konto K [--feld CSS]` (2FA-Umzug vom Microsoft Authenticator, 25.10.): liest den Einrichtungsschlüssel von der Seite (aus `--feld`, sonst der eine sichtbare Text, der wie Base32 aussieht, oder ein `otpauth:`-Link; mehrere oder keiner = Fehler), gleiche Prüfung wie `fuell` (eigener https-Tab, Host passt, Stufe), prüft Base32 (mindestens 16 Zeichen) und schreibt `totp` des Eintrags (neues `geaendert`, PUT mit If-Match, bei 409 neu). Ein alter Schlüssel geht in das eigene Feld `totpVerlauf` (`[{totp, bis}]`, höchstens 5; nicht in `passwortVerlauf`, damit die App dort keine Schlüssel zeigt). Ausgabe nur `gesetzt: NAME (HOST)`, Schlüssel nie in stdout, argv, Log.
- `heimherz erlaubt HOST [--auftrag DATEI]`: prüft nur die Stufe (ohne Tresor), Exit 0 erlaubt, 7 verweigert mit Grund. `claude-bw fuell` ruft es vor jedem Füllen, damit Bitwarden dieselben Stufen hat.
- `heimherz stufen`: zeigt die Tabelle unten und das erkannte Modell.

### Stufen (höchste zuerst)
| Stufe | Seiten | Wer darf füllen |
|---|---|---|
| 1 Bank | Sparkasse (`spkvr.de`, `sparkasse.de`), `tink.com` | nur Opus, und nur mit Auftrag-Datei, die ausdrücklich Sparkasse + anmelden + allein/nicht zuhause sagt; jedes Füllen meldet Ahmed eine Mitteilung |
| 2 Kündigen und Verträge, Versicherung, Gesundheit, Steuer | Mobilfunk, Strom, Fitness, Streaming, Versand, Krankenkasse, Versicherung, ELSTER | nur Opus |
| 3 Amt | Arbeitsagentur, Jobcenter, Familienkasse, Stadt, Land | Opus oder Sonnet |
| 4 Konten | Google, Apple, GitHub, Cloudflare, Microsoft | Opus oder Sonnet |
| 5 Rest | alles andere | Opus, Sonnet, unbekanntes Modell |
Haiku: nichts. Die Liste steht in `bin/stufen.ts`; unbekannte Seite = Stufe 5.

Was der Agent danach auf der Seite tun darf (senden, kündigen, zahlen), regeln weiter die globalen Regeln; die Stufe regelt nur, wer sich einloggen darf.

### Modell erkennen
`CLAUDE_PID` → `/proc/<pid>/cmdline` → `--model`. Fehlt es: `ANTHROPIC_MODEL`, sonst unbekannt. Ehrliche Grenze: Unteragenten haben dieselbe Umgebung wie die Hauptsitzung (geprüft 25.10.), ein Sonnet-Unteragent einer Opus-Sitzung zählt darum als Opus. Die Regel "Bank nie an Unteragenten" bleibt Regel, die Mitteilung an Ahmed ist die Kontrolle.

### Auftrag-Datei (Stufe 1)
`--auftrag DATEI` oder Umgebung `HEIMHERZ_AUFTRAG`. Gültig nur, wenn die Datei unter `~/.claude/buero-stand/`, `~/Documents/Obsidian/Personal/` oder `~/projects/` liegt, höchstens 24 Stunden alt ist und eine Zeile enthält, die Sparkasse, anmelden oder einloggen und allein, selber/selbst oder "nicht zuhause" nennt (selber seit Ahmed 25.10.: "Sparkasse prüft … ich helfe bei der Anmeldung … Er soll alles selber machen"). Ehrliche Grenze: auch ein Agent kann so eine Datei schreiben (alles läuft als `tobi`); darum die Mitteilung bei jedem Bank-Füllen und das Protokoll.

### Protokoll
`~/.local/state/heimherz/fuell.log` (0600): Zeit, Host, Eintrag-id, Feldart, Stufe, Modell, erlaubt/verweigert, Auftrag-Pfad. Nie Werte.

### Phase 2 (nicht in diesem Schritt)
- Bestätigungscode aus der Mail (`mailcode --von ABSENDER`): Code aus dem eigenen Gmail-Tab direkt ins Feld, ohne dass der Agent ihn sieht.
- Bitwarden-Wache schreibt neue Logins auch nach Heimherz.
- `claude-bw fuell` füllt aus Heimherz statt aus `bw` (nach Ahmeds Entscheidung zu Bitwarden, etwa 22.11.).

### Prüfung
`bun test` grün: Stufen je Seite und Modell, Auftrag-Datei (gültig, zu alt, falscher Ort, ohne "allein"), TOTP gegen `fixtures/totp/rfc6238.json`, Eintragswahl (Host, Unterdomain, fremde Seite, Doppelte, Code nur mit TOTP), CDP-Füllen gegen einen Wegwerf-Chrome mit Testseite (kein echter Tresor). Echt: Füllen der Arbeitsagentur-Anmeldung aus Heimherz in der Opus-Sitzung; Sparkasse ohne Auftrag-Datei wird verweigert.

## 24. Modul `passkeys` (W-025, 25.10.2026)

Ahmed: "Es sagt bei heim kein passkeys. Ich will natürlich dass passkeys auch klappen" (iOS Einstellungen, Automatisch ausfüllen: bei Heim nur "Passwörter und Codes", bei Bitwarden "Passkeys, Passwörter und Codes").

Ziel: Heim ist ein vollwertiger Passkey-Anbieter. Die Einstellungen zeigen "Passkeys, Passwörter und Codes"; Anmelden mit einem Passkey aus dem Tresor klappt; neue Passkeys einer Seite landen im Tresor und gehen mit dem nächsten Abgleich an den PC. Ersetzt Abschnitt 14 "Passkeys: eigener Schritt" und Abschnitt 2 "Passkeys: Phase 2".

- Info.plist der Erweiterung: `ProvidesPasskeys` = true.
- Format (unverändert, SPEC 9): Feld `passkeys` am Login = Liste `{credentialId, rpId, userName, userDisplayName, userHandle, key}`, `credentialId`/`userHandle`/`key` Base64url, `key` = privater P-256-Schlüssel PKCS#8. Neue Passkeys bekommen zusätzlich `erstellt` (ISO). Bitwarden-Feld `bitwardenFido2` wird gelesen: `keyValue` (PKCS#8, Base64url oder Base64), `credentialId` als UUID (16 Bytes) oder `b64.<Base64url>`, `userHandle` Base64url oder Base64, nur `keyAlgorithm` ECDSA / `keyCurve` P-256. Unlesbare Passkeys fallen still weg (nicht anbieten, nicht löschen).
- Identitäten: je lesbarem Passkey eines lebendigen Logins eine `ASPasskeyCredentialIdentity` (rpId, userName, credentialID, userHandle, `recordIdentifier` = Eintrag-id), neben den Passwort- und Code-Identitäten. Nie der Schlüssel.
- Anmelden (`ASPasskeyCredentialRequest`): Kandidaten = Passkeys mit genau gleicher rpId (WebAuthn, keine Unterdomain-Regel), bei gewählter Identität genau deren credentialID, sonst gefiltert nach `allowedCredentials`. authenticatorData = SHA-256(rpId) ‖ Flags UP|UV|BE|BS (0x1D) ‖ signCount 0 (4 Bytes); Signatur ECDSA P-256 (CryptoKit, DER) über authenticatorData ‖ clientDataHash. Ohne Blatt nur bei offenem Entsperr-Fenster (wie Passwörter, Abschnitt 10), sonst Blatt mit Face ID. Liste (`prepareCredentialList(for:requestParameters:)`): ein Kandidat = sofort nach Face ID, mehrere = Auswahl, keiner = die gewohnte Passwortliste für die rpId.
- Neu anlegen (`prepareInterface(forPasskeyRegistration:)`): nur ES256 (-7) aus `supportedAlgorithms`; liegt schon ein Passkey aus `excludedCredentials` im Tresor, Abbruch. Nach Face ID P-256-Schlüssel erzeugen, credentialId 16 Zufallsbytes, Attestation "none": CBOR `{"fmt":"none","attStmt":{},"authData":…}`, authData mit Flags UP|UV|AT|BE|BS (0x5D), AAGUID 16 Nullbytes, COSE-Schlüssel `{1:2, 3:-7, -1:1, -2:x, -3:y}`. Ablage: Login mit gleichem Benutzer (ohne Groß/Klein) und passendem Host bekommt den Passkey dazu, sonst neuer Login (Name und URL aus rpId). Speichern wie beim Passwort (lokal verschlüsselt, höchstens 6 s Abgleich, Identitäten neu).
- Grenzen: signCount immer 0 (synchronisierte Passkeys, wie Apple und Bitwarden; `shortcut:` im Code). Kein bedingtes Anlegen ohne Blatt (`SupportsConditionalPasskeyRegistration` aus), keine Erweiterungen (PRF, largeBlob). Am PC (`heimherz export bitwarden`) gehen eigene `passkeys` nicht mit, nur `bitwardenFido2`.
- Prüfung: XCTest mit festen Testvektoren (authenticatorData Byte für Byte, CBOR der Attestation, Signatur prüft mit dem öffentlichen Schlüssel, Bitwarden-UUID-Kennung, Base64/Base64url, Identitäten, Ablauf im Modell mit Attrappen). Nur am Gerät: Einstellungen zeigen "Passkeys, Passwörter und Codes", Anmelden bei github.com und webauthn.io, Anlegen bei webauthn.io.
