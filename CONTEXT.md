# Begriffe

- Tresor: alle Einträge (Logins, Notizen) als JSON, nur verschlüsselt gespeichert oder gesendet.
- Umschlag: verschlüsselter Tresor `{v, rev, nonce, daten}` (SPEC 5). Der Server kennt nur ihn.
- Tresorschlüssel (K): 32 Byte, am PC in `systemd-creds`, am Handy im Schlüsselbund.
- rev: Fassung des Umschlags am Server, `PUT` nur mit passender `If-Match`.
- Grabstein: gelöschter Eintrag mit `geloescht: true`, bleibt 90 Tage, damit die Löschung auf allen Geräten ankommt.
- Gerät: ein gekoppeltes Handy oder das CLI, mit eigenem Token.
- Koppeln: QR am PC (`heimherz koppeln`) mit URL, Token und K; das Handy scannt ihn einmal.
- Kennung (Foto): SHA-256 von `PHAsset.localIdentifier`, b64url ohne Füllzeichen.
- Ressource (Foto): eine Datei eines Assets (Foto, gepaartes Video, Video).
