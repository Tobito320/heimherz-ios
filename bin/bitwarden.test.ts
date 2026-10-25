import { expect, test } from 'bun:test';
import fx from '../fixtures/bitwarden/export-beispiel.json';
import { nachBitwarden, vonBitwarden } from './bitwarden';

test('Export-Beispiel: Zählung; nur der Papierkorb wird übersprungen, Karten, Identitäten und SSH-Schlüssel kommen als Notiz mit', () => {
  const r = vonBitwarden(fx);
  expect({ l: r.logins, n: r.notizen, u: r.uebersprungen, a: r.anhaenge }).toEqual({ l: 3, n: 4, u: 1, a: 1 });
  expect(r.eintraege.map(e => e.id.slice(-1))).toEqual(['1', '2', '3', '4', '5', '6', '8']);
  expect(vonBitwarden({ items: [null, 5, { type: 9 }, { type: 6 }] }).uebersprungen).toBe(4);
});

test('Login: alle Felder, Bitwarden-id bleibt, Datum wird geaendert', () => {
  const [shop] = vonBitwarden(fx).eintraege;
  expect(shop).toEqual({
    id: 'b0000000-0000-4000-8000-000000000001', art: 'login', name: 'Beispiel Shop', benutzer: 'erika@example.org', passwort: 'Erfunden-Passwort-111!',
    urls: ['https://shop.example.org/login', 'https://www.shop.example.org/'], totp: 'otpauth://totp/Shop:erika?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Shop',
    notiz: 'Erfundene Notiz zum Shop\n\n--- Felder aus Bitwarden ---\nKundennummer: K-4711-erfunden\nSicherheitsfrage: Erfundene-Antwort-555\nNewsletter: true',
    favorit: true, geaendert: '2026-09-01T10:00:00.000Z', geloescht: false,
    bitwardenFelder: (fx.items[0] as any).fields, bitwardenVerlauf: (fx.items[0] as any).passwordHistory, bitwardenUriMatch: [null, 3],
  });
});

test('Passkey-Feld bleibt unverändert als bitwardenFido2, fehlende Felder werden leer', () => {
  const [, passkey, ohne, notiz] = vonBitwarden(fx).eintraege;
  expect(passkey.bitwardenFido2).toEqual((fx.items[1].login as any).fido2Credentials);
  expect(ohne).toMatchObject({ benutzer: '', urls: [], totp: '', notiz: '', favorit: false });
  expect(Object.keys(ohne).filter(k => k.startsWith('bitwarden'))).toEqual([]);
  expect(passkey.bitwardenReprompt).toBe(1);
  expect(notiz).toMatchObject({ art: 'notiz', passwort: '', benutzer: '', notiz: 'Erfundenes WLAN: Heimnetz\nSchlüssel: nicht-echt-123' });
});

test('Karte, Identität und SSH-Schlüssel: Notiz mit allen Feldern als Text, kein Verlust', () => {
  const [, , , , karte, ident, ssh] = vonBitwarden(fx).eintraege;
  expect(karte).toMatchObject({ art: 'notiz', name: 'Erfundene Karte', notiz: '--- Karte ---\ncardholderName: Erika Beispiel\nbrand: Visa\nnumber: 4111111111111111\nexpMonth: 12\nexpYear: 2030\ncode: 000' });
  expect(ident.notiz).toBe('--- Identität ---\nfirstName: Erika\nlastName: Beispiel');
  expect(ssh.notiz).toContain('Nur zum Testen\n\n--- SSH-Schlüssel ---\nprivateKey: -----BEGIN FAKE KEY-----\nZXJmdW5kZW4=\n-----END FAKE KEY-----\npublicKey: ssh-ed25519 AAAAerfunden test@example.org\nkeyFingerprint: SHA256:erfunden');
});

test('auch die Ausgabe von `bw list items` (nackte Liste) wird gelesen; Müll ergibt nichts', () => {
  expect(vonBitwarden(fx.items).logins).toBe(3);
  expect(vonBitwarden(null)).toMatchObject({ eintraege: [], logins: 0, notizen: 0, uebersprungen: 0 });
  expect(vonBitwarden({ items: [null, 5, { type: 9 }] }).uebersprungen).toBe(3);
});

test('rund: Import, Export, nochmal Import gibt dieselben Logins', () => {
  const eins = vonBitwarden(fx);
  const aus = nachBitwarden({ format: 1, eintraege: eins.eintraege });
  expect(aus).toMatchObject({ encrypted: false, folders: [] });
  expect(aus.items).toHaveLength(7);
  const zwei = vonBitwarden(aus);
  expect(zwei.eintraege).toEqual(eins.eintraege);
  const shop = aus.items.find(i => i.name === 'Beispiel Shop') as any;
  expect(shop).toMatchObject({ notes: 'Erfundene Notiz zum Shop', fields: (fx.items[0] as any).fields, passwordHistory: (fx.items[0] as any).passwordHistory });
  expect(shop.login.uris.map((u: any) => u.match)).toEqual([null, 3]);
  expect(aus.items.find(i => i.name === 'Passkey-Seite')).toMatchObject({ reprompt: 1 });
  expect(aus.items.find(i => i.name === 'Erfundene Karte')).toMatchObject({ type: 2, notes: expect.stringContaining('number: 4111111111111111') });
  const passkey = aus.items.find(i => i.type === 1 && (i as any).login.fido2Credentials) as any;
  expect(passkey.login.fido2Credentials).toEqual((fx.items[1].login as any).fido2Credentials);
});

test('Export lässt Grabsteine weg und kennt Notizen als secureNote', () => {
  const e = vonBitwarden(fx).eintraege;
  const aus = nachBitwarden({ format: 1, eintraege: [{ ...e[0], geloescht: true }, e[3]] });
  expect(aus.items).toHaveLength(1);
  expect(aus.items[0]).toMatchObject({ type: 2, secureNote: { type: 0 }, name: 'WLAN-Zettel' });
});
