// Foto-Empfang (SPEC 6): Rohdaten gestreamt nach .teil, dann umbenannt nach JJJJ/MM/<datum>_<name>. fotos.db merkt, was schon da ist.
import { Database } from 'bun:sqlite';
import { mkdirSync, rmSync, statfsSync } from 'node:fs';
import { join } from 'node:path';
import { json, leer } from './http';
import { legeOhneUeberschreibenAb, loescheLeise, streameInDatei } from './dateiio';

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const zwei = (n: number) => String(n).padStart(2, '0');

// Dateiname vom Handy: ohne Pfadtrenner und Steuerzeichen, höchstens 200 Zeichen (Endung bleibt).
export function bereinigeName(roh: string | null): string {
  let n = roh ?? '';
  try { n = decodeURIComponent(n); } catch { /* war nicht kodiert */ }
  n = n.replace(/[\/\\\u0000-\u001f\u007f]/g, '_').trim();
  if (n === '' || n === '.' || n === '..') n = 'datei';
  if (n.length > 200) {
    const p = n.lastIndexOf('.');
    const ext = p > 0 && n.length - p <= 20 ? n.slice(p) : '';
    n = n.slice(0, 200 - ext.length) + ext;
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

  constructor(private ordner: string, daten: string) {
    mkdirSync(ordner, { recursive: true });
    this.teil = join(ordner, '.teil');
    rmSync(this.teil, { recursive: true, force: true }); // Reste abgebrochener Läufe (nur unser eigener Ordner)
    mkdirSync(this.teil, { recursive: true });
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
    const cl = req.headers.get('content-length');
    const da = this.db.query('SELECT groesse FROM fotos WHERE kennung = ? AND ressource = ?').get(kennung, ressource) as { groesse: number } | null;
    if (da && cl !== null && Number(cl) === da.groesse) return json({ schon: true });
    if (this.laeuft.has(schluessel)) return leer(409);
    this.laeuft.add(schluessel);

    const temp = join(this.teil, `${kennung}_${ressource}.teil`);
    try {
      loescheLeise(temp);
      let n: number;
      try { n = await streameInDatei(req, temp); } catch { loescheLeise(temp); return leer(400); }
      if (da && da.groesse === n) { loescheLeise(temp); return json({ schon: true }); } // Länge kam ohne Content-Length
      const { jahr, monat, stempel } = zeitName(req.headers.get('x-aufnahme'));
      const name = `${stempel}_${bereinigeName(req.headers.get('x-dateiname'))}`;
      const ziel = legeOhneUeberschreibenAb(temp, join(this.ordner, jahr, monat), name);
      this.db.query('INSERT OR REPLACE INTO fotos (kennung, ressource, groesse, pfad, empfangen) VALUES (?, ?, ?, ?, ?)').run(kennung, ressource, n, ziel, new Date().toISOString());
      return json({ gespeichert: true });
    } finally {
      this.laeuft.delete(schluessel);
      loescheLeise(temp);
    }
  }
}
