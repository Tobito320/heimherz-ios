import { expect, test } from 'bun:test';
import fx from '../fixtures/bitwarden/export-beispiel.json';
import { nachBitwarden, vonBitwarden } from './bitwarden';

test('Export-Beispiel: Zählung, Papierkorb und fremde Typen werden übersprungen', () => {
  const r = vonBitwarden(fx);
  expect({ l: r.logins, n: r.notizen, u: r.uebersprungen }).toEqual({ l: 3, n: 1, u: 3 });
  expect(r.eintraege.map(e => e.id)).toEqual(['b0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000004']);
});

test('Login: alle Felder, Bitwarden-id bleibt, Datum wird geaendert', () => {
  const [shop] = vonBitwarden(fx).eintraege;
  expect(shop).toEqual({
    id: 'b0000000-0000-4000-8000-000000000001', art: 'login', name: 'Beispiel Shop', benutzer: 'erika@example.org', passwort: 'Erfunden-Passwort-111!',
    urls: ['https://shop.example.org/login', 'https://www.shop.example.org/'], totp: 'otpauth://totp/Shop:erika?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Shop',
    notiz: 'Erfundene Notiz zum Shop', favorit: true, geaendert: '2026-09-01T10:00:00.000Z', geloescht: false,
  });
});

test('Passkey-Feld bleibt unverändert als bitwardenFido2, fehlende Felder werden leer', () => {
  const [, passkey, ohne, notiz] = vonBitwarden(fx).eintraege;
  expect(passkey.bitwardenFido2).toEqual((fx.items[1].login as any).fido2Credentials);
  expect(ohne).toMatchObject({ benutzer: '', urls: [], totp: '', notiz: '', favorit: false });
  expect('bitwardenFido2' in ohne).toBe(false);
  expect(notiz).toMatchObject({ art: 'notiz', passwort: '', benutzer: '', notiz: 'Erfundenes WLAN: Heimnetz\nSchlüssel: nicht-echt-123' });
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
  expect(aus.items).toHaveLength(4);
  const zwei = vonBitwarden(aus);
  expect(zwei.eintraege).toEqual(eins.eintraege);
  const passkey = aus.items.find(i => i.type === 1 && (i as any).login.fido2Credentials) as any;
  expect(passkey.login.fido2Credentials).toEqual((fx.items[1].login as any).fido2Credentials);
});

test('Export lässt Grabsteine weg und kennt Notizen als secureNote', () => {
  const e = vonBitwarden(fx).eintraege;
  const aus = nachBitwarden({ format: 1, eintraege: [{ ...e[0], geloescht: true }, e[3]] });
  expect(aus.items).toHaveLength(1);
  expect(aus.items[0]).toMatchObject({ type: 2, secureNote: { type: 0 }, name: 'WLAN-Zettel' });
});
