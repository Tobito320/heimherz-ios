// Foto-Analyse am PC (SPEC 25 A): Gleiche (SHA-256), Ähnliche (dHash), Unscharfe (Laplace), Größte. Nur Lesen von Fotos und Videos;
// Löschen geht ausschließlich über den Papierkorb-Befehl (trash-put), nie über rm. Eigene Datenbankverbindung zu fotos.db (WAL),
// damit der laufende Dienst weiter schreiben kann.
import { Database } from 'bun:sqlite';
import { lstatSync } from 'node:fs';
import { basename, extname, join, relative, resolve, sep } from 'node:path';
import { json, leer, liesBegrenzt } from './http';
import { artVon, MAGICK_FORMAT } from './vorschau';

export const HAMMING_MAX = 6;
// shortcut: an Ahmeds Fotos geschätzt (Varianz des Laplace-Filters auf 256 px, Grau 0-255); nachstellen nach seinem Feedback.
export const UNSCHARF_SCHWELLE = 30;
// shortcut: dHash mit weniger gesetzten Bits (fast einfarbig) oder fast nur gesetzten gilt nicht als Beleg für "ähnlich" (sonst kettet Union-Find alle dunklen Bilder).
export const MIN_BITS = 8;
const GROESSTE_MAX = 500;
const TEXT_MAX = 200;

const HAUPT = ['foto-0', 'video-0'];
const FORMAT: Record<string, string> = { ...MAGICK_FORMAT, dng: 'dng' };

// ---------- reine Rechnung ----------

export type Grau = { w: number; h: number; daten: Uint8Array };

// Mittelwert je Zelle, auch bei Quellen unter 9x8 Pixeln.
function zelle(g: Grau, x: number, y: number, bw: number, bh: number): number {
  const x0 = Math.floor(x * g.w / bw), x1 = Math.max(Math.floor((x + 1) * g.w / bw), x0 + 1);
  const y0 = Math.floor(y * g.h / bh), y1 = Math.max(Math.floor((y + 1) * g.h / bh), y0 + 1);
  let s = 0, n = 0;
  for (let j = y0; j < y1 && j < g.h; j++) for (let i = x0; i < x1 && i < g.w; i++) { s += g.daten[j * g.w + i]; n++; }
  return n ? s / n : 0;
}

// 64 Bit: je Zeile (8) und Spalte (8) "links heller als rechts" aus einem 9x8-Graubild, als 16 Hex-Zeichen.
export function dhash(g: Grau): string {
  let hi = 0, lo = 0;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    const bit = zelle(g, x, y, 9, 8) > zelle(g, x + 1, y, 9, 8) ? 1 : 0;
    if (y < 4) hi = (hi << 1 | bit) >>> 0; else lo = (lo << 1 | bit) >>> 0;
  }
  return hi.toString(16).padStart(8, '0') + lo.toString(16).padStart(8, '0');
}

const bits = (n: number) => { n -= (n >>> 1) & 0x55555555; n = (n & 0x33333333) + ((n >>> 2) & 0x33333333); return (((n + (n >>> 4)) & 0x0f0f0f0f) * 0x01010101) >>> 24; };
const teile = (h: string): [number, number] => [parseInt(h.slice(0, 8), 16) >>> 0, parseInt(h.slice(8), 16) >>> 0];
export const hamming = (a: string, b: string) => { const [a1, a2] = teile(a), [b1, b2] = teile(b); return bits((a1 ^ b1) >>> 0) + bits((a2 ^ b2) >>> 0); };
export const gesetzteBits = (h: string) => { const [a, b] = teile(h); return bits(a) + bits(b); };

// Varianz der Laplace-Antwort (4er-Nachbarschaft) über das Innere des Bildes: hoch = scharf.
export function schaerfe(g: Grau): number {
  if (g.w < 3 || g.h < 3) return 0;
  let s = 0, q = 0, n = 0;
  for (let y = 1; y < g.h - 1; y++) for (let x = 1; x < g.w - 1; x++) {
    const i = y * g.w + x, d = g.daten;
    const l = d[i - 1] + d[i + 1] + d[i - g.w] + d[i + g.w] - 4 * d[i];
    s += l; q += l * l; n++;
  }
  const m = s / n;
  return q / n - m * m;
}

// Union-Find über Indizes; gibt die Gruppen mit mindestens zwei Mitgliedern zurück.
export function gruppiereAehnliche(items: { id: string; dhash: string }[], max = HAMMING_MAX): string[][] {
  const t = items.map(i => teile(i.dhash));
  const eltern = items.map((_, i) => i);
  const wurzel = (i: number): number => { while (eltern[i] !== i) { eltern[i] = eltern[eltern[i]]; i = eltern[i]; } return i; };
  for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) {
    if (bits((t[i][0] ^ t[j][0]) >>> 0) + bits((t[i][1] ^ t[j][1]) >>> 0) <= max) eltern[wurzel(j)] = wurzel(i);
  }
  const m = new Map<number, string[]>();
  items.forEach((it, i) => { const w = wurzel(i); (m.get(w) ?? m.set(w, []).get(w)!).push(it.id); });
  return [...m.values()].filter(g => g.length > 1);
}

export type Kandidat = { kennung: string; pixel: number; bearbeitet: boolean; schaerfe: number; aufnahme: string };

// Reihenfolge: höchste Auflösung, bearbeitet, am schärfsten, ältestes; zuletzt die Kennung (damit der Vorschlag bei jedem Lauf gleich ausfällt).
export function waehleBehalten(k: Kandidat[]): { behalten: string; grund: string } {
  let rest = k, grund: string | null = null;
  const schritt = (text: string, wert: (c: Kandidat) => number, besser: 1 | -1, spiel = 0) => {
    const best = rest.reduce((a, c) => (wert(c) - wert(a)) * besser > 0 ? c : a);
    const bleibt = rest.filter(c => (wert(best) - wert(c)) * besser <= spiel * Math.abs(wert(best)));
    if (bleibt.length < rest.length && grund === null) grund = text;
    rest = bleibt;
  };
  schritt('höchste Auflösung', c => c.pixel, 1);
  schritt('bearbeitet', c => c.bearbeitet ? 1 : 0, 1);
  schritt('am schärfsten', c => c.schaerfe, 1, 0.05);
  const aelteste = [...rest].sort((a, b) => a.aufnahme.localeCompare(b.aufnahme))[0].aufnahme;
  const alt = rest.filter(c => c.aufnahme === aelteste);
  if (alt.length < rest.length && grund === null) grund = 'ältestes';
  rest = alt;
  const gewaehlt = rest.sort((a, b) => a.kennung.localeCompare(b.kennung))[0];
  return { behalten: gewaehlt.kennung, grund: grund ?? 'gleich gut, Kopie' };
}

// ---------- Merkmale aus der Datei ----------

export type Merkmale = { sha256: string | null; dhash: string | null; schaerfe: number | null; breite: number | null; hoehe: number | null };
export type Merkmalgeber = (pfad: string, art: 'foto' | 'video') => Promise<Merkmale>;

const NICE = ['nice', '-n', '19'];

async function lauf(argv: string[], zeitlimitMs: number, stdin?: Blob): Promise<Uint8Array> {
  const p = Bun.spawn([...NICE, ...argv], { stdin: stdin ?? 'ignore', stdout: 'pipe', stderr: 'ignore' });
  let zuSpaet = false;
  const uhr = setTimeout(() => { zuSpaet = true; p.kill('SIGKILL'); }, zeitlimitMs);
  try {
    const [aus, code] = await Promise.all([new Response(p.stdout).arrayBuffer(), p.exited]);
    if (zuSpaet) throw new Error('Zeitlimit');
    if (code !== 0) throw new Error(`${argv[0]} Code ${code}`);
    return new Uint8Array(aus);
  } finally { clearTimeout(uhr); }
}

// "P5\nW H\n255\n" plus Bytes; Kommentarzeilen erlaubt.
export function lesePgm(b: Uint8Array): Grau {
  let pos = 0;
  const wort = (): string => {
    while (pos < b.length && (b[pos] === 0x20 || b[pos] === 0x0a || b[pos] === 0x0d || b[pos] === 0x09 || b[pos] === 0x23)) {
      if (b[pos] === 0x23) while (pos < b.length && b[pos] !== 0x0a) pos++; else pos++;
    }
    const von = pos;
    while (pos < b.length && ![0x20, 0x0a, 0x0d, 0x09].includes(b[pos])) pos++;
    return new TextDecoder().decode(b.subarray(von, pos));
  };
  if (wort() !== 'P5') throw new Error('kein PGM');
  const w = Number(wort()), h = Number(wort()); wort(); pos++;
  if (!(w > 0 && h > 0) || b.length - pos < w * h) throw new Error('PGM zu kurz');
  return { w, h, daten: b.subarray(pos, pos + w * h) };
}

async function sha256Datei(pfad: string): Promise<string> {
  const h = new Bun.CryptoHasher('sha256');
  for await (const teil of Bun.file(pfad).stream()) h.update(teil);
  return h.digest('hex');
}

const grauMerkmale = (g: Grau, breite: number, hoehe: number) => ({ dhash: dhash(g), schaerfe: schaerfe(g), breite, hoehe });

async function bildMerkmale(pfad: string, endung: string) {
  const aus = await lauf(['magick', '-limit', 'memory', '1GiB', '-limit', 'map', '2GiB', '-limit', 'disk', '2GiB', '-limit', 'time', '60',
    `${FORMAT[endung]}:-[0]`, '-auto-orient', '-print', '%w %h\n', '-thumbnail', '256x256>', '-colorspace', 'Gray', '-depth', '8', 'pgm:-'], 90_000, Bun.file(pfad));
  const nl = aus.indexOf(0x0a);
  const [breite, hoehe] = new TextDecoder().decode(aus.subarray(0, nl)).split(' ').map(Number);
  return grauMerkmale(lesePgm(aus.subarray(nl + 1)), breite, hoehe);
}

async function videoMerkmale(pfad: string) {
  const bild = async (ab: string) => lauf(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-ss', ab, '-i', `file:${pfad}`, '-frames:v', '1', '-an', '-sn',
    '-vf', 'scale=w=256:h=256:force_original_aspect_ratio=decrease,format=gray', '-f', 'image2pipe', '-c:v', 'pgm', '-'], 120_000);
  let aus = new Uint8Array();
  try { aus = await bild('1'); } catch { /* weiter mit 0 */ }
  if (aus.length === 0) aus = await bild('0'); // Video unter einer Sekunde: ffmpeg endet mit Code 0 ohne Bild
  const maße = new TextDecoder().decode(await lauf(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', `file:${pfad}`], 30_000)).trim().split(',').map(Number);
  return grauMerkmale(lesePgm(aus), maße[0] || 0, maße[1] || 0);
}

// Die Prüfsumme gelingt immer, wenn die Datei lesbar ist; scheitert die Dekodierung, bleiben die übrigen Felder leer (die Zeile gilt trotzdem als gerechnet).
export const echteMerkmale: Merkmalgeber = async (pfad, art) => {
  const sha256 = await sha256Datei(pfad);
  const leerM = { dhash: null, schaerfe: null, breite: null, hoehe: null };
  const a = artVon(pfad), endung = extname(pfad).slice(1).toLowerCase();
  try {
    if (art === 'video' ? a?.art === 'video' : a?.art === 'bild' || endung === 'dng') {
      return { sha256, ...(art === 'video' ? await videoMerkmale(pfad) : await bildMerkmale(pfad, endung)) };
    }
  } catch { /* kaputt oder nicht lesbar */ }
  return { sha256, ...leerM };
};

// ---------- Entprellen ----------

// Höchstens ein Lauf zugleich; Auslöser während eines Laufs bewirken genau einen weiteren danach.
export class Entprellt {
  private uhr: ReturnType<typeof setTimeout> | null = null;
  private laeuft = false;
  private nochmal = false;
  constructor(private ms: number, private tu: () => Promise<unknown>) {}
  ausloesen() {
    if (this.laeuft) { this.nochmal = true; return; }
    if (this.uhr) clearTimeout(this.uhr);
    this.uhr = setTimeout(() => { this.uhr = null; void this.starte(); }, this.ms);
    this.uhr.unref?.();
  }
  stoppe() { if (this.uhr) clearTimeout(this.uhr); this.uhr = null; }
  private async starte() {
    this.laeuft = true;
    try { await this.tu(); } catch (e) { console.error('Analyse:', (e as Error)?.message); } finally { this.laeuft = false; }
    if (this.nochmal) { this.nochmal = false; this.ausloesen(); }
  }
}

// ---------- Analyse ----------

export type Gruppe = { art: 'gleich' | 'aehnlich'; kennungen: string[]; behalten: string; grund: string };
type Zeile = { kennung: string; ressource: string; groesse: number; pfad: string; empfangen: string };
type Merk = { kennung: string; ressource: string; groesse: number; sha256: string | null; dhash: string | null; schaerfe: number | null; breite: number | null; hoehe: number | null };
export type Optionen = { papierkorb?: string[]; merkmale?: Merkmalgeber; parallel?: number };

const bereinigeText = (s: string) => s.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, TEXT_MAX);

export class Analyse {
  private db: Database;
  private ordner: string;
  private laeuft: Promise<LaufErgebnis> | null = null;
  private papierkorb: string[];
  private merkmale: Merkmalgeber;
  private parallel: number;

  constructor(daten: string, ordner: string, o: Optionen = {}) {
    this.ordner = resolve(ordner);
    this.papierkorb = o.papierkorb ?? ['trash-put'];
    this.merkmale = o.merkmale ?? echteMerkmale;
    this.parallel = o.parallel ?? 4;
    this.db = new Database(join(daten, 'fotos.db'), { create: true });
    this.db.run('PRAGMA journal_mode = WAL');
    this.db.run('PRAGMA busy_timeout = 10000');
    this.db.run('CREATE TABLE IF NOT EXISTS fotos (kennung TEXT NOT NULL, ressource TEXT NOT NULL, groesse INTEGER NOT NULL, pfad TEXT NOT NULL, empfangen TEXT NOT NULL, PRIMARY KEY (kennung, ressource))');
    this.db.run('CREATE TABLE IF NOT EXISTS analyse (kennung TEXT NOT NULL, ressource TEXT NOT NULL, groesse INTEGER NOT NULL, sha256 TEXT, dhash TEXT, schaerfe REAL, breite INTEGER, hoehe INTEGER, PRIMARY KEY (kennung, ressource))');
    this.db.run('CREATE TABLE IF NOT EXISTS geloescht (kennung TEXT NOT NULL, ressource TEXT NOT NULL, groesse INTEGER NOT NULL, pfad TEXT NOT NULL, empfangen TEXT NOT NULL, geloescht TEXT NOT NULL, PRIMARY KEY (kennung, ressource))');
    this.db.run('CREATE TABLE IF NOT EXISTS vorschlag (behalten TEXT PRIMARY KEY, grund TEXT NOT NULL, zeit TEXT NOT NULL)');
    this.db.run('CREATE TABLE IF NOT EXISTS analyse_meta (schluessel TEXT PRIMARY KEY, wert TEXT NOT NULL)');
  }

  schliesse() { this.db.close(); }

  private unter(pfad: string): boolean { const p = resolve(pfad); return p.startsWith(this.ordner + sep); }

  // Hauptdateien (foto-0, sonst video-0), die neu sind oder deren Größe sich geändert hat.
  private offeneZeilen(): Zeile[] {
    return this.db.query(`
      SELECT f.kennung, f.ressource, f.groesse, f.pfad, f.empfangen FROM fotos f
      LEFT JOIN analyse a ON a.kennung = f.kennung AND a.ressource = f.ressource
      WHERE (f.ressource = 'foto-0' OR (f.ressource = 'video-0' AND NOT EXISTS (SELECT 1 FROM fotos g WHERE g.kennung = f.kennung AND g.ressource = 'foto-0')))
        AND (a.kennung IS NULL OR a.groesse <> f.groesse)
      ORDER BY f.empfangen DESC`).all() as Zeile[];
  }

  rechne(): Promise<LaufErgebnis> {
    return this.laeuft ??= this.rechneEinmal().finally(() => { this.laeuft = null; });
  }

  private async rechneEinmal(): Promise<LaufErgebnis> {
    const start = performance.now();
    const offen = this.offeneZeilen();
    let gerechnet = 0, fehlt = 0, unlesbar = 0;
    const schreibe = this.db.query('INSERT OR REPLACE INTO analyse (kennung, ressource, groesse, sha256, dhash, schaerfe, breite, hoehe) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    let naechste = 0;
    const arbeiter = async () => {
      while (naechste < offen.length) {
        const z = offen[naechste++];
        if (!this.unter(z.pfad)) { fehlt++; continue; }
        try { lstatSync(z.pfad); } catch { fehlt++; continue; } // Datei weg: später wieder versuchen
        let m: Merkmale;
        try { m = await this.merkmale(z.pfad, z.ressource === 'video-0' ? 'video' : 'foto'); } catch { m = { sha256: null, dhash: null, schaerfe: null, breite: null, hoehe: null }; unlesbar++; } // Zeile trotzdem: sonst bliebe `offen` für immer über 0
        schreibe.run(z.kennung, z.ressource, z.groesse, m.sha256, m.dhash, m.schaerfe, m.breite, m.hoehe); // klein und einzeln: der Dienst darf zwischendurch schreiben
        gerechnet++;
      }
    };
    await Promise.all(Array.from({ length: Math.min(this.parallel, offen.length) }, arbeiter));
    this.db.query("INSERT OR REPLACE INTO analyse_meta (schluessel, wert) VALUES ('stand', ?)").run(new Date().toISOString());
    return { gerechnet, nichtLesbar: unlesbar, fehlt, offen: this.offeneZeilen().length, sekunden: Math.round((performance.now() - start) / 100) / 10 };
  }

  private metaStand(): string | null { return (this.db.query("SELECT wert FROM analyse_meta WHERE schluessel = 'stand'").get() as { wert: string } | null)?.wert ?? null; }

  assets(): number { return (this.db.query('SELECT COUNT(DISTINCT kennung) AS n FROM fotos').get() as { n: number }).n; }

  private ueberschreibungen(): Map<string, string> {
    return new Map((this.db.query('SELECT behalten, grund FROM vorschlag ORDER BY zeit').all() as { behalten: string; grund: string }[]).map(r => [r.behalten, r.grund]));
  }

  // Gruppen mit Einzelheiten (für Antwort und CLI).
  gruppenMitDaten() {
    const merk = this.db.query(`SELECT a.kennung, a.ressource, a.groesse, a.sha256, a.dhash, a.schaerfe, a.breite, a.hoehe FROM analyse a
      JOIN fotos f ON f.kennung = a.kennung AND f.ressource = a.ressource AND f.groesse = a.groesse`).all() as Merk[];
    const info = new Map<string, { pfad: string; empfangen: string }>();
    for (const z of this.db.query("SELECT kennung, pfad, empfangen, ressource FROM fotos WHERE ressource IN ('foto-0','video-0')").all() as Zeile[]) info.set(z.kennung + '/' + z.ressource, z);
    const bearbeitet = new Set((this.db.query("SELECT DISTINCT kennung FROM fotos WHERE ressource LIKE 'alternative-%'").all() as { kennung: string }[]).map(r => r.kennung));
    const ueber = this.ueberschreibungen();
    const nach = new Map(merk.map(m => [m.kennung, m]));
    const kand = (kennung: string): Kandidat => {
      const m = nach.get(kennung)!, i = info.get(kennung + '/' + m.ressource)!;
      return { kennung, pixel: (m.breite ?? 0) * (m.hoehe ?? 0), bearbeitet: bearbeitet.has(kennung), schaerfe: m.schaerfe ?? 0, aufnahme: basename(i.pfad).slice(0, 19) || i.empfangen };
    };
    const gruppe = (art: Gruppe['art'], ids: string[]): Gruppe => {
      const ueberschrieben = ids.filter(k => ueber.has(k)).pop(); // zuletzt gesetzter Vorschlag
      const w = ueberschrieben ? { behalten: ueberschrieben, grund: ueber.get(ueberschrieben)! } : waehleBehalten(ids.map(kand));
      return { art, kennungen: [w.behalten, ...ids.filter(k => k !== w.behalten).sort()], behalten: w.behalten, grund: w.grund };
    };

    const gruppen: Gruppe[] = [];
    const inGleich = new Set<string>();
    const nachSha = new Map<string, string[]>();
    for (const m of merk) if (m.sha256) (nachSha.get(m.sha256) ?? nachSha.set(m.sha256, []).get(m.sha256)!).push(m.kennung);
    for (const ids of nachSha.values()) if (ids.length > 1) { gruppen.push(gruppe('gleich', ids)); ids.forEach(k => inGleich.add(k)); }
    for (const ressource of ['foto-0', 'video-0']) { // Fotos und Videos getrennt
      const pool = merk.filter(m => m.ressource === ressource && m.dhash && !inGleich.has(m.kennung) && gesetzteBits(m.dhash) >= MIN_BITS && gesetzteBits(m.dhash) <= 64 - MIN_BITS)
        .map(m => ({ id: m.kennung, dhash: m.dhash! }));
      for (const ids of gruppiereAehnliche(pool)) gruppen.push(gruppe('aehnlich', ids));
    }
    const groesse = (k: string) => nach.get(k)!.groesse;
    const verschwendet = (g: Gruppe) => g.kennungen.filter(k => k !== g.behalten).reduce((s, k) => s + groesse(k), 0);
    gruppen.sort((a, b) => verschwendet(b) - verschwendet(a) || a.behalten.localeCompare(b.behalten));
    return { gruppen, merk: nach, info };
  }

  antwort() {
    const { gruppen, merk, info } = this.gruppenMitDaten();
    const istPng = (m: Merk) => info.get(m.kennung + '/' + m.ressource)!.pfad.toLowerCase().endsWith('.png'); // Screenshots nie als unscharf
    const unscharf = [...merk.values()].filter(m => m.ressource === 'foto-0' && m.schaerfe !== null && m.schaerfe < UNSCHARF_SCHWELLE && !istPng(m))
      .sort((a, b) => a.schaerfe! - b.schaerfe!).map(m => m.kennung);
    const groesste = this.db.query('SELECT kennung, SUM(groesse) AS bytes FROM fotos GROUP BY kennung ORDER BY bytes DESC, kennung LIMIT ?').all(GROESSTE_MAX) as { kennung: string; bytes: number }[];
    return { stand: this.metaStand(), gerechnet: merk.size, offen: this.offeneZeilen().length, gruppen, unscharf, groesste };
  }

  // Für das CLI (`gruppen`): Kennungen, Größen und Pfade relativ zum Fotos-Ordner, damit ein Agent die Bilder ansehen kann.
  gruppenDetails() {
    const { gruppen, merk, info } = this.gruppenMitDaten();
    const bytes = new Map((this.db.query('SELECT kennung, SUM(groesse) AS b FROM fotos GROUP BY kennung').all() as { kennung: string; b: number }[]).map(r => [r.kennung, r.b]));
    return gruppen.map(g => ({
      art: g.art, behalten: g.behalten, grund: g.grund,
      assets: g.kennungen.map(k => {
        const m = merk.get(k)!;
        return { kennung: k, bytes: bytes.get(k) ?? m.groesse, pfad: relative(this.ordner, info.get(k + '/' + m.ressource)!.pfad), breite: m.breite, hoehe: m.hoehe, schaerfe: m.schaerfe === null ? null : Math.round(m.schaerfe) };
      }),
    }));
  }

  // Für das CLI: Gruppe zu einer beliebigen Mitglieds-Kennung.
  gruppeVon(kennung: string): Gruppe | null { return this.gruppenMitDaten().gruppen.find(g => g.kennungen.includes(kennung)) ?? null; }

  setzeVorschlag(kennung: string, behalten: string, grund: string): boolean {
    const g = this.gruppeVon(kennung);
    if (!g || !g.kennungen.includes(behalten)) return false;
    for (const k of g.kennungen) this.db.query('DELETE FROM vorschlag WHERE behalten = ?').run(k); // je Gruppe gilt nur der letzte Vorschlag
    this.db.query('INSERT OR REPLACE INTO vorschlag (behalten, grund, zeit) VALUES (?, ?, ?)').run(behalten, bereinigeText(grund) || 'von Hand gewählt', new Date().toISOString());
    return true;
  }

  // Dateien dieser Assets in den Papierkorb (nie löschen). Erst der Papierkorb-Befehl, dann wandern die Zeilen nach `geloescht`.
  async inPapierkorb(kennungen: string[]): Promise<{ verschoben: number; fehler: number }> {
    let verschoben = 0, fehler = 0;
    const ids = [...new Set(kennungen)];
    for (const k of ids) {
      const zeilen = this.db.query('SELECT kennung, ressource, groesse, pfad, empfangen FROM fotos WHERE kennung = ?').all(k) as Zeile[];
      if (zeilen.length === 0) continue; // unbekannt: zählt nicht
      let ok = true;
      for (const z of zeilen) {
        let da = true;
        try { lstatSync(z.pfad); } catch { da = false; }
        if (!da) continue; // schon weg: Zeile wandert trotzdem
        if (!this.unter(z.pfad)) { ok = false; break; } // nie etwas außerhalb des Fotos-Ordners anfassen
        try { ok = (await Bun.spawn([...this.papierkorb, z.pfad], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' }).exited) === 0; } catch { ok = false; }
        if (!ok) break;
      }
      if (!ok) { fehler++; continue; }
      const jetzt = new Date().toISOString();
      this.db.transaction(() => {
        for (const z of zeilen) this.db.query('INSERT OR REPLACE INTO geloescht (kennung, ressource, groesse, pfad, empfangen, geloescht) VALUES (?, ?, ?, ?, ?, ?)').run(z.kennung, z.ressource, z.groesse, z.pfad, z.empfangen, jetzt);
        this.db.query('DELETE FROM fotos WHERE kennung = ?').run(k);
        this.db.query('DELETE FROM analyse WHERE kennung = ?').run(k);
        this.db.query('DELETE FROM vorschlag WHERE behalten = ?').run(k);
      })();
      verschoben++;
    }
    return { verschoben, fehler };
  }

  // HTTP
  antworte(): Response { return json(this.antwort()); }

  async papierkorbRoute(req: Request): Promise<Response> {
    let k: unknown;
    try { k = JSON.parse(new TextDecoder().decode(await liesBegrenzt(req, 1024 * 1024))).kennungen; } catch { return leer(400); }
    if (!Array.isArray(k) || k.length > 20_000 || !k.every(x => typeof x === 'string')) return leer(400);
    return json(await this.inPapierkorb(k as string[]));
  }
}

export type LaufErgebnis = { gerechnet: number; nichtLesbar: number; fehlt: number; offen: number; sekunden: number };
