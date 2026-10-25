// `heimherz tempo [MINUTEN]` (SPEC 7): fasst foto-tempo.jsonl zusammen, damit man sieht, wo beim Foto-Abgleich die Zeit hängt.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { TempoZeile } from '../server/tempo';

export function leseTempo(daten: string): TempoZeile[] {
  const z: TempoZeile[] = [];
  for (const datei of ['foto-tempo.jsonl.1', 'foto-tempo.jsonl']) {
    const pfad = join(daten, datei);
    if (!existsSync(pfad)) continue;
    for (const zeile of readFileSync(pfad, 'utf8').split('\n')) {
      try { if (zeile) z.push(JSON.parse(zeile)); } catch { /* halbe Zeile am Ende */ }
    }
  }
  return z;
}

const mittel = (a: number[]) => a.reduce((s, x) => s + x, 0) / a.length;
const p90 = (a: number[]) => [...a].sort((x, y) => x - y)[Math.ceil(a.length * 0.9) - 1];
const ms = (a: (number | null)[]) => {
  const w = a.filter((x): x is number => x !== null);
  return w.length ? `Ø ${Math.round(mittel(w))} ms, p90 ${p90(w)} ms (${w.length} Werte)` : 'keine Werte';
};
const schnitt = (a: (number | null)[]) => { const w = a.filter((x): x is number => x !== null); return w.length ? mittel(w).toFixed(1) : '-'; };
const anteil = (n: number, von: number) => (von ? `${Math.round((100 * n) / von)} %` : '-');

// Das Fenster endet bei der letzten Zeile (nicht bei "jetzt"), damit man auch Stunden nach dem Test noch ablesen kann.
export function fasseTempo(alle: TempoZeile[], minuten = 10): string[] {
  if (!alle.length) return ['Keine Messwerte (foto-tempo.jsonl leer oder fehlt).'];
  const ende = Math.max(...alle.map(z => Date.parse(z.zeit)));
  const z = alle.filter(x => Date.parse(x.zeit) >= ende - minuten * 60_000);
  const neu = z.filter(x => x.ergebnis === 'neu');
  const start = Math.min(...z.map(x => Date.parse(x.zeit) - x.empfangMs));
  const sek = Math.max(1, (ende - start) / 1000);
  const bytes = neu.reduce((s, x) => s + x.bytes, 0);
  const empfangSek = neu.reduce((s, x) => s + x.empfangMs, 0) / 1000;
  const aus: string[] = [
    `Fenster: ${minuten} Min. bis ${new Date(ende).toISOString().slice(11, 19)} UTC, ${Math.round(sek)} s Spanne`,
    `Angekommen: ${neu.length} Dateien, ${(bytes / 1e6).toFixed(1)} MB  =>  ${(bytes / 1e6 / sek).toFixed(2)} MB/s, ${(neu.length / sek).toFixed(2)} Dateien/s`,
    `Ergebnisse: neu ${neu.length}, schon da ${z.filter(x => x.ergebnis === 'schon').length}, abgebrochen ${z.filter(x => x.ergebnis === 'abbruch').length}`,
  ];
  if (!neu.length) return aus;
  aus.push(
    `Export (Handy): ${ms(neu.map(x => x.exportMs))}`,
    `Warten (Export fertig bis Upload-Start): ${ms(neu.map(x => x.warteMs))}`,
    `Empfang (Server): ${ms(neu.map(x => x.empfangMs))}`,
    `Empfang je Upload: ${empfangSek > 0 ? (bytes / 1e6 / empfangSek).toFixed(2) : '-'} MB/s; Ø gleichzeitig am Server: ${(empfangSek / sek).toFixed(1)}`,
    `Handy meldet im Mittel: ${schnitt(neu.map(x => x.aktiv))} Uploads, ${schnitt(neu.map(x => x.exporte))} Exporte`,
    `Vordergrund: ${anteil(neu.filter(x => x.vordergrund === 1).length, neu.filter(x => x.vordergrund !== null).length)}; Session vorder ${neu.filter(x => x.session === 'vorder').length}, hinter ${neu.filter(x => x.session === 'hinter').length}`,
    `Durchgang: lokal ${neu.filter(x => x.durchgang === 'lokal').length}, icloud ${neu.filter(x => x.durchgang === 'icloud').length}`,
    `Arten: ${[...new Set(neu.map(x => x.art))].sort().map(a => `${a} ${neu.filter(x => x.art === a).length}`).join(', ')}`,
  );
  return aus;
}
