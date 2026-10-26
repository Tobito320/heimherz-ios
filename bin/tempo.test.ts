import { expect, test } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fasseTempo, leseTempo } from './tempo';
import type { TempoZeile } from '../server/tempo';

const zeile = (sek: number, o: Partial<TempoZeile> = {}): TempoZeile => ({
  zeit: new Date(Date.UTC(2026, 9, 25, 15, 24, sek)).toISOString(), bytes: 1_000_000, empfangMs: 1000, gesamtMs: 1000, ergebnis: 'neu', art: 'foto',
  exportMs: 100, warteMs: 50, aktiv: 6, exporte: 2, vordergrund: 1, durchgang: 'lokal', session: 'vorder', ...o,
});

test('Zusammenfassung: Rate, Mittel, p90, Vordergrund-Anteil', () => {
  // 10 Uploads, je 1 MB, Ende nach 1..10 s; Start der ersten bei 0 s => Spanne 10 s
  const z = Array.from({ length: 10 }, (_, i) => zeile(i + 1, { exportMs: (i + 1) * 100, vordergrund: i < 7 ? 1 : 0, session: i < 7 ? 'vorder' : 'hinter' }));
  const t = fasseTempo(z, 10).join('\n');
  expect(t).toContain('10 Dateien, 10.0 MB  =>  1.00 MB/s, 1.00 Dateien/s');
  expect(t).toContain('Export (Handy): Ø 550 ms, p90 900 ms');
  expect(t).toContain('Empfang (Server): Ø 1000 ms, p90 1000 ms');
  expect(t).toContain('Ø gleichzeitig am Server: 1.0');
  expect(t).toContain('Vordergrund: 70 %; Session vorder 7, hinter 3');
});

test('Fenster endet bei der letzten Zeile; ältere fallen heraus; schon und abbruch zählen nicht als Bytes', () => {
  const z = [zeile(1), zeile(2), { ...zeile(3), ergebnis: 'schon' as const, bytes: 0 }, { ...zeile(4), ergebnis: 'abbruch' as const, bytes: 0 }];
  const spaet = { ...zeile(0), zeit: new Date(Date.UTC(2026, 9, 25, 16, 30, 0)).toISOString() };
  const t = fasseTempo([...z, spaet], 1).join('\n');
  expect(t).toContain('Angekommen: 1 Dateien');
  expect(fasseTempo(z, 5).join('\n')).toContain('Ergebnisse: neu 2, schon da 1, abgebrochen 1');
});

test('leer und fehlende Werte brechen nicht', () => {
  expect(fasseTempo([])[0]).toContain('Keine Messwerte');
  const t = fasseTempo([zeile(1, { exportMs: null, warteMs: null, aktiv: null, exporte: null, vordergrund: null, session: null, durchgang: null })]).join('\n');
  expect(t).toContain('Export (Handy): keine Werte');
  expect(t).toContain('Vordergrund: -');
});

test('leseTempo liest .1 und Hauptdatei, ignoriert halbe Zeile', () => {
  const d = mkdtempSync(join(tmpdir(), 'tempo-cli-'));
  writeFileSync(join(d, 'foto-tempo.jsonl.1'), JSON.stringify(zeile(1)) + '\n');
  writeFileSync(join(d, 'foto-tempo.jsonl'), JSON.stringify(zeile(2)) + '\n{"zeit":');
  expect(leseTempo(d)).toHaveLength(2);
  rmSync(d, { recursive: true, force: true });
});

test('Leerlauf: Lücke zwischen Uploads wird gezählt, überlappende Uploads nicht doppelt', () => {
  // Uploads je 1 s lang, zwei überlappend (Ende 1 s und 1,5 s), dann 8 s nichts, dann einer (Ende 11 s): Spanne 0..11 s
  const z = [zeile(1), { ...zeile(1), zeit: new Date(Date.UTC(2026, 9, 25, 15, 24, 1, 500)).toISOString() }, zeile(11)];
  const t = fasseTempo(z, 10).join('\n');
  expect(t).toContain('Lücken über 3 s: 1, größte 8.5 s');
  expect(t).toContain('Leerlauf am Server (kein Upload läuft): 77 %');  // besetzt 0..1,5 und 10..11 = 2,5 von 11 s
  const dicht = Array.from({ length: 10 }, (_, i) => zeile(i + 1));
  expect(fasseTempo(dicht, 10).join('\n')).toContain('Leerlauf am Server (kein Upload läuft): 0 %, Lücken über 3 s: 0, größte 0.0 s');
});

test('Ablegen danach = gesamtMs minus empfangMs', () => {
  const t = fasseTempo([zeile(1, { gesamtMs: 1300 }), zeile(2, { gesamtMs: 1500 })]).join('\n');
  expect(t).toContain('Ablegen danach (Server, gesamt minus Empfang): Ø 400 ms');
});

test('Zähler je Lauf: zurückgestellt und Hänger, höchster Wert im Fenster; ohne Werte keine Zeile', () => {
  const t = fasseTempo([zeile(1, { aufgeschoben: 3, haenger: 0 }), zeile(2, { aufgeschoben: 40, haenger: 1 })], 10).join('\n');
  expect(t).toContain('Nach iCloud zurückgestellt: 40; Export hing und wurde abgebrochen: 1');
  expect(fasseTempo([zeile(1)], 10).join('\n')).not.toContain('zurückgestellt');
});
