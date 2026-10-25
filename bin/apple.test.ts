import { expect, test } from 'bun:test';
import { csvZeilen, ausCsv, uebernimm } from './apple';
import type { Eintrag, Tresor } from '../lib/zusammenfuehren';

// Erfundene Daten im Format von Apple Passwörter (Mac/Windows-Export) und Chrome
const APPLE = 'Title,URL,Username,Password,Notes,OTPAuth\n'
  + 'Beispiel (tobi),https://www.example.org/login,tobi,Alt-Passwort-1,,\n'
  + '"Shop, mit Komma",https://shop.example.net,"anna@example.net","p""w,1","Zeile 1\nZeile 2",otpauth://totp/Shop:anna?secret=GEZDGNBV\n'
  + 'Nur Notiz,,,,"geheime Notiz",\n';
const CHROME = 'name,url,username,password,note\nForum,https://forum.example.com/,max,f0rum,\n';

const e = (x: Partial<Eintrag>): Eintrag => ({ id: 'x', art: 'login', name: '', benutzer: '', passwort: '', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00.000Z', geloescht: false, ...x });
const JETZT = new Date('2026-10-25T05:00:00.000Z');

test('CSV mit Anführungszeichen, Kommas, Zeilenumbrüchen', () => {
  const z = csvZeilen(APPLE);
  expect(z.length).toBe(4);
  expect(z[2]).toEqual(['Shop, mit Komma', 'https://shop.example.net', 'anna@example.net', 'p"w,1', 'Zeile 1\nZeile 2', 'otpauth://totp/Shop:anna?secret=GEZDGNBV']);
});

test('Apple- und Chrome-Kopfzeile werden erkannt', () => {
  const a = ausCsv(APPLE);
  expect(a.map(x => [x.name, x.benutzer, x.passwort, x.urls[0] ?? '', x.totp, x.art])).toEqual([
    ['Beispiel (tobi)', 'tobi', 'Alt-Passwort-1', 'https://www.example.org/login', '', 'login'],
    ['Shop, mit Komma', 'anna@example.net', 'p"w,1', 'https://shop.example.net', 'otpauth://totp/Shop:anna?secret=GEZDGNBV', 'login'],
    ['Nur Notiz', '', '', '', '', 'notiz'],
  ]);
  expect(ausCsv(CHROME)[0]).toMatchObject({ name: 'Forum', benutzer: 'max', passwort: 'f0rum' });
  expect(() => ausCsv('a,b\n1,2\n')).toThrow();
});

test('Übernehmen: neu, anderes Passwort oder neuer Code = aktualisiert mit Verlauf, zweiter Lauf gleich', () => {
  const bestehend: Tresor = { format: 1, eintraege: [
    e({ id: 'b1', name: 'Beispiel', benutzer: 'tobi', passwort: 'Neu-Passwort-2', urls: ['https://example.org'] }),
    e({ id: 'b2', name: 'Shop', benutzer: 'anna@example.net', passwort: 'p"w,1', urls: ['https://shop.example.net/a'] }),
  ] };
  const { tresor, neu, aktualisiert, gleich } = uebernimm(bestehend, ausCsv(APPLE), JETZT);
  expect([neu, aktualisiert, gleich]).toEqual([1, 2, 0]);
  const b1 = tresor.eintraege.find(x => x.id === 'b1')!;
  expect(b1.passwort).toBe('Alt-Passwort-1');
  expect(b1.geaendert).toBe(JETZT.toISOString());
  expect(b1.passwortVerlauf).toEqual([{ passwort: 'Neu-Passwort-2', bis: JETZT.toISOString() }]);
  const b2 = tresor.eintraege.find(x => x.id === 'b2')!;
  expect(b2.totp).toBe('otpauth://totp/Shop:anna?secret=GEZDGNBV');
  expect(b2.passwortVerlauf).toBeUndefined(); // gleiches Passwort: kein Verlauf
  // zweiter Lauf ändert nichts
  const zwei = uebernimm(tresor, ausCsv(APPLE), JETZT);
  expect([zwei.neu, zwei.aktualisiert, zwei.gleich]).toEqual([0, 0, 3]);
});

test('Grabsteine zählen nicht als vorhanden, gleicher Host + Benutzer auf anderer Seite bleibt getrennt', () => {
  const bestehend: Tresor = { format: 1, eintraege: [e({ id: 'g', benutzer: 'tobi', urls: ['https://example.org'], geloescht: true }), e({ id: 'z', benutzer: 'tobi', passwort: 'x', urls: ['https://anders.example'] })] };
  const r = uebernimm(bestehend, ausCsv(APPLE), JETZT);
  expect(r.neu).toBe(3);
});
