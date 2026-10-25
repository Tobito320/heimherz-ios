// Geräte-Token (SPEC 6): geraete.json im Datenordner, nur SHA-256 der Token. Das CLI schreibt dieselbe Datei.
import { closeSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, statSync, writeSync } from 'node:fs';
import { timingSafeEqual } from 'node:crypto';
import { dirname, join } from 'node:path';

export type Geraet = { id: string; name: string; hash: string; angelegt: string; zuletzt: string | null };

export const hashe = (token: string) => new Bun.CryptoHasher('sha256').update(token).digest('hex');
export const neuesToken = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url');

// Temp + fsync + rename: nie eine halbe Datei, auch bei Absturz.
export function schreibeAtomar(pfad: string, daten: string | Uint8Array, modus = 0o600) {
  mkdirSync(dirname(pfad), { recursive: true });
  const temp = `${pfad}.${process.pid}.${crypto.randomUUID().slice(0, 8)}.tmp`;
  const fd = openSync(temp, 'w', modus);
  try { writeSync(fd, daten); fsyncSync(fd); } finally { closeSync(fd); }
  renameSync(temp, pfad);
}

export const geraetePfad = (daten: string) => join(daten, 'geraete.json');

export function leseGeraete(daten: string): Geraet[] {
  try {
    const x = JSON.parse(readFileSync(geraetePfad(daten), 'utf8'));
    return Array.isArray(x) ? x : [];
  } catch { return []; }
}

export const schreibeGeraete = (daten: string, liste: Geraet[]) => schreibeAtomar(geraetePfad(daten), JSON.stringify(liste, null, 1));

const MINUTE = 60_000;

export class Geraete {
  private liste: Geraet[] = [];
  private stand = '';
  constructor(private daten: string) {}

  // Datei nur neu lesen, wenn mtime oder Größe sich geändert haben (das CLI schreibt sie von außen).
  private lade() {
    let s = '';
    try { const st = statSync(geraetePfad(this.daten), { bigint: true }); s = `${st.mtimeNs}:${st.size}`; } catch { /* fehlt = keine Geräte */ }
    if (s !== this.stand) { this.liste = s ? leseGeraete(this.daten) : []; this.stand = s; }
  }

  // Zeitkonstant gegen alle Hashes, kein früher Abbruch.
  pruefe(token: string | null): Geraet | null {
    if (!token) return null;
    this.lade();
    const h = Buffer.from(hashe(token));
    let treffer: Geraet | null = null;
    for (const g of this.liste) {
      const x = Buffer.from(String(g.hash));
      if (x.length === h.length && timingSafeEqual(x, h)) treffer = g;
    }
    if (treffer) this.merkeZuletzt(treffer.id);
    return treffer;
  }

  // Höchstens einmal pro Minute schreiben; frisch von der Platte lesen, damit Änderungen des CLI nicht verloren gehen.
  private merkeZuletzt(id: string) {
    const jetzt = Date.now();
    const g = this.liste.find(x => x.id === id);
    if (!g || (g.zuletzt && jetzt - Date.parse(g.zuletzt) < MINUTE)) return;
    const frisch = leseGeraete(this.daten);
    const f = frisch.find(x => x.id === id);
    if (!f) return;
    f.zuletzt = new Date(jetzt).toISOString();
    schreibeGeraete(this.daten, frisch);
    this.stand = '';
  }
}
