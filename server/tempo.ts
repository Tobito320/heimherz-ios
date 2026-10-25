// Foto-Tempo (SPEC 6): je Upload eine Zeile mit nur Zahlen und Stichwörtern in foto-tempo.jsonl (0600, höchstens 20.000 Zeilen, dann rotieren).
// Die Zahlen schickt die App als Kopfzeilen X-Heim-*; Inhalte, Namen und Kennungen stehen nie drin.
import { appendFileSync, chmodSync, existsSync, readFileSync, renameSync } from 'node:fs';
import { join } from 'node:path';

export const TEMPO_MAX_ZEILEN = 20_000;

export type TempoZeile = {
  zeit: string; bytes: number; empfangMs: number; ergebnis: 'neu' | 'schon' | 'abbruch'; art: string;
  exportMs: number | null; warteMs: number | null; aktiv: number | null; exporte: number | null;
  vordergrund: 0 | 1 | null; durchgang: 'lokal' | 'icloud' | null; session: 'vorder' | 'hinter' | null;
};

const ARTEN = ['foto', 'video', 'live', 'alternative', 'ton'];
const ganzzahl = (v: string | null) => (v !== null && /^\d{1,9}$/.test(v) ? Number(v) : null);
const wahl = <T extends string>(v: string | null, erlaubt: readonly T[]): T | null => (erlaubt as readonly string[]).includes(v ?? '') ? (v as T) : null;

export function tempoKopf(h: Headers, ressource: string): Pick<TempoZeile, 'art' | 'exportMs' | 'warteMs' | 'aktiv' | 'exporte' | 'vordergrund' | 'durchgang' | 'session'> {
  const v = h.get('x-heim-vordergrund');
  return {
    art: ARTEN.find(a => ressource.startsWith(a + '-')) ?? 'andere',
    exportMs: ganzzahl(h.get('x-heim-export-ms')), warteMs: ganzzahl(h.get('x-heim-warte-ms')),
    aktiv: ganzzahl(h.get('x-heim-aktiv')), exporte: ganzzahl(h.get('x-heim-exporte')),
    vordergrund: v === '1' ? 1 : v === '0' ? 0 : null,
    durchgang: wahl(h.get('x-heim-durchgang'), ['lokal', 'icloud']), session: wahl(h.get('x-heim-session'), ['vorder', 'hinter']),
  };
}

export class TempoLog {
  private datei: string;
  private zeilen = 0;

  constructor(daten: string, private max = TEMPO_MAX_ZEILEN) {
    this.datei = join(daten, 'foto-tempo.jsonl');
    if (existsSync(this.datei)) {
      try { chmodSync(this.datei, 0o600); this.zeilen = readFileSync(this.datei, 'utf8').split('\n').length - 1; } catch { /* Messung ist nie wichtiger als der Upload */ }
    }
  }

  schreibe(z: TempoZeile) {
    try {
      if (this.zeilen >= this.max) { renameSync(this.datei, this.datei + '.1'); this.zeilen = 0; }
      appendFileSync(this.datei, JSON.stringify(z) + '\n', { mode: 0o600 });
      this.zeilen++;
    } catch { /* wie oben */ }
  }
}
