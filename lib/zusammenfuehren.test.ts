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
