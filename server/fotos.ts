// Foto-Empfang (SPEC 6): Rohdaten gestreamt nach .teil, dann umbenannt nach JJJJ/MM/<datum>_<name>. fotos.db merkt, was schon da ist.
import { Database } from 'bun:sqlite';
import { mkdirSync, rmSync, statfsSync } from 'node:fs';
import { join } from 'node:path';
import { json, leer } from './http';
import { TempoLog, tempoKopf } from './tempo';
import { ablegeFehler, legeOhneUeberschreibenAb, loescheLeise, MINDEST_FREI, pruefeUpload, streameInDatei } from './dateiio';

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const zwei = (n: number) => String(n).padStart(2, '0');

// Höchstens `max` UTF-8-Bytes, geschnitten an einer Zeichengrenze (nie mitten in einem Zeichen).
function kuerze(s: string, max: number): string {
  let aus = '', bytes = 0;
  for (const z of s) { bytes += Buffer.byteLength(z); if (bytes > max) break; aus += z; }
  return aus;
}

// Dateiname vom Handy: ohne Pfadtrenner und Steuerzeichen, höchstens 200 UTF-8-Bytes (Endung bleibt).
export function bereinigeName(roh: string | null): string {
  let n = roh ?? '';
  try { n = decodeURIComponent(n); } catch { /* war nicht kodiert */ }
  n = n.replace(/[\/\\\u0000-\u001f\u007f]/g, '_').trim();
  if (n === '' || n === '.' || n === '..') n = 'datei';
  if (Buffer.byteLength(n) > 200) {
    const p = n.lastIndexOf('.');
    const ext = p > 0 && Buffer.byteLength(n.slice(p)) <= 20 ? n.slice(p) : '';
    n = kuerze(ext ? n.slice(0, p) : n, 200 - Buffer.byteLength(ext)) + ext;
  }
  return n;
}

export function zeitName(aufnahme: string | null, jetzt = new Date()): { jahr: string; monat: string; stempel: string } {
  let d = aufnahme ? new Date(aufnahme) : jetzt;
  if (isNaN(d.getTime())) d = jetzt;
  const jahr = String(d.getFullYear()), monat = zwei(d.getMonth() + 1);
  return { jahr, monat, stempel: `${jahr}-${monat}-${zwei(d.getDate())}_${zwei(d.getHours())}-${zwei(d.getMinutes())}-${zwei(d.getSeconds())}` };
}

export class Fotos {
  private db: Database;
  private teil: string;
  private laeuft = new Set<string>();
  private tempo: TempoLog;

  constructor(private ordner: string, daten: string, private mindestFrei = MINDEST_FREI) {
    mkdirSync(ordner, { recursive: true, mode: 0o700 });
    this.teil = join(ordner, '.teil');
    rmSync(this.teil, { recursive: true, force: true }); // Reste abgebrochener Läufe (nur unser eigener Ordner)
    mkdirSync(this.teil, { recursive: true, mode: 0o700 });
    this.tempo = new TempoLog(daten);
    this.db = new Database(join(daten, 'fotos.db'), { create: true });
    this.db.run('PRAGMA journal_mode = WAL');
    this.db.run('CREATE TABLE IF NOT EXISTS fotos (kennung TEXT NOT NULL, ressource TEXT NOT NULL, groesse INTEGER NOT NULL, pfad TEXT NOT NULL, empfangen TEXT NOT NULL, PRIMARY KEY (kennung, ressource))');
  }

  anzahl(): number { return (this.db.query('SELECT COUNT(*) AS n FROM fotos').get() as { n: number }).n; }

  bekannt(): Response {
    return json(this.db.query('SELECT kennung, ressource, groesse FROM fotos ORDER BY empfangen, kennung, ressource').all());
  }

  speicher() {
    const s = statfsSync(this.ordner);
    return { belegt: (s.blocks - s.bfree) * s.bsize, frei: s.bavail * s.bsize };
  }

  async empfange(req: Request, kennung: string, ressource: string): Promise<Response> {
    if (!ID.test(kennung) || !ID.test(ressource)) return leer(400);
    const schluessel = `${kennung}/${ressource}`;
    const start = performance.now();
    const messe = (ergebnis: 'neu' | 'schon' | 'abbruch', bytes: number, ms = Math.round(performance.now() - start)) =>
      this.tempo.schreibe({ zeit: new Date().toISOString(), bytes, empfangMs: ms, ergebnis, ...tempoKopf(req.headers, ressource) });
    const cl = req.headers.get('content-length');
    const da = this.db.query('SELECT groesse FROM fotos WHERE kennung = ? AND ressource = ?').get(kennung, ressource) as { groesse: number } | null;
    if (da && cl !== null && Number(cl) === da.groesse) { messe('schon', 0); return json({ schon: true }); }
    if (this.laeuft.has(schluessel)) return leer(409);
    const abgelehnt = pruefeUpload(req, this.ordner, this.mindestFrei, false);
    if (abgelehnt) return abgelehnt;
    this.laeuft.add(schluessel);

    const temp = join(this.teil, `${kennung}_${ressource}.teil`);
    try {
      loescheLeise(temp);
      let n: number;
      try { n = await streameInDatei(req, temp); } catch (e) { loescheLeise(temp); messe('abbruch', 0); return ablegeFehler(e) ?? leer(400); }
      const empfangMs = Math.round(performance.now() - start);
      if (da && da.groesse === n) { loescheLeise(temp); return json({ schon: true }); } // Länge kam ohne Content-Length
      const { jahr, monat, stempel } = zeitName(req.headers.get('x-aufnahme'));
      const name = `${stempel}_${bereinigeName(req.headers.get('x-dateiname'))}`;
      let ziel: string;
      try { ziel = legeOhneUeberschreibenAb(temp, join(this.ordner, jahr, monat), name); } catch (e) {
        const r = ablegeFehler(e);
        if (r) return r;
        throw e;
      }
      this.db.query('INSERT OR REPLACE INTO fotos (kennung, ressource, groesse, pfad, empfangen) VALUES (?, ?, ?, ?, ?)').run(kennung, ressource, n, ziel, new Date().toISOString());
      messe('neu', n, empfangMs);
      return json({ gespeichert: true });
    } finally {
      this.laeuft.delete(schluessel);
      loescheLeise(temp);
    }
  }
}
