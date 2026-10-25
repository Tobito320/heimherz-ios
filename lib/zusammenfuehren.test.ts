import { expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { zusammenfuehren } from './zusammenfuehren';

const ordner = new URL('../fixtures/merge/', import.meta.url).pathname;
for (const datei of readdirSync(ordner).filter(d => d.endsWith('.json'))) {
  const f = JSON.parse(readFileSync(ordner + datei, 'utf8'));
  test(`Merge-Fixture ${f.beschreibung}`, () => {
    expect(zusammenfuehren(f.a, f.b, new Date(f.jetzt))).toEqual(f.erwartet);
    // Reihenfolge egal: beide Geräte kommen auf dieselben Einträge
    expect(zusammenfuehren(f.b, f.a, new Date(f.jetzt)).eintraege).toEqual(f.erwartet.eintraege);
  });
}

// Papierkorb ("Gelöscht"): Der Grabstein behält seine Felder. Der Merge bleibt dabei dieselbe Regel (neueres geaendert gewinnt).
import type { Eintrag, Tresor } from './zusammenfuehren';
const eintrag = (extra: Partial<Eintrag> = {}): Eintrag => ({
  id: 'a', art: 'login', name: 'GitHub', benutzer: 'mia', passwort: 'geheim', urls: ['https://github.com'], totp: '', notiz: '', favorit: false,
  geaendert: '2026-10-25T10:00:00.000Z', geloescht: false, ...extra,
});
const tresor = (...e: Eintrag[]): Tresor => ({ format: 1, eintraege: e });
const jetzt = new Date('2026-10-28T00:00:00.000Z');

test('Grabstein mit Feldern: Wiederherstellen (neueres geaendert) gewinnt, Endgültig löschen gewinnt, Reihenfolge egal', () => {
  const stein = eintrag({ geloescht: true, geaendert: '2026-10-26T10:00:00.000Z' });
  const zurueck = eintrag({ geloescht: false, geaendert: '2026-10-27T10:00:00.000Z' });
  const leer = eintrag({ name: '', benutzer: '', passwort: '', urls: [], geloescht: true, geaendert: '2026-10-27T11:00:00.000Z' });
  for (const [x, y] of [[tresor(stein), tresor(zurueck)], [tresor(zurueck), tresor(stein)]]) {
    expect(zusammenfuehren(x, y, jetzt).eintraege).toEqual([zurueck]);
  }
  expect(zusammenfuehren(tresor(eintrag()), tresor(stein), jetzt).eintraege[0].geloescht).toBe(true);
  expect(zusammenfuehren(zusammenfuehren(tresor(stein), tresor(zurueck), jetzt), tresor(leer), jetzt).eintraege).toEqual([leer]);
  expect(zusammenfuehren(tresor(stein), tresor(leer), jetzt).eintraege[0].passwort).toBe('');
});
