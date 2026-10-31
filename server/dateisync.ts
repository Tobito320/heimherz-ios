// Dateien-Sync für die Dateien-App am Handy (SPEC 31): stabile Kennungen, Änderungsabfrage mit Anker, Ersetzen, Umbenennen/Verschieben,
// Ordner anlegen, Papierkorb. Jeder Pfad geht durch dieselben realpath-Prüfungen wie `Dateien`; Kennungen kommen aus dem Dateisystem
// (Gerät, Inode, Geburtszeit), also bleiben sie beim Umbenennen und Verschieben am PC oder vom Handy gleich. Nichts davon liegt auf der Platte.
import { copyFileSync, lstatSync, mkdirSync, readdirSync, renameSync, statSync, type BigIntStats } from 'node:fs';
import { join, relative } from 'node:path';
import { Dateien, NichtDa, Verboten } from './dateien';
import { ablegeFehler, loescheLeise, pruefeUpload, streameInDatei } from './dateiio';
import { json, leer, liesBegrenzt } from './http';

const MAX_EINTRAEGE = 200_000; // shortcut: bei mehr Einträgen bricht die Abfrage mit 500 ab (nie ein halber Baum, der wie Löschen aussähe); bei Millionen Dateien Index statt Durchlauf
const MAX_LOG = 50_000;
const FRISCH_MS = 2_000; // so oft höchstens liest der Dienst den Baum neu
const MAX_NAME_BYTES = 200;
// Ordner, auf die Werkzeuge am PC zählen (Sortier-Lauf, Sicherung, Lumen Wallet) oder die die App als Kategorie zeigt: vom Handy nicht umbenennen, verschieben, löschen. Gleiche Liste: `SyncRegeln.geschuetzteOrdner`.
const GESCHUETZT = new Set(['Aboherz', 'Bürokratie', 'Eingang', 'Projekte', 'Sicherung', 'Weitere']);

class Konflikt extends Error { constructor(public aktuell?: Eintrag) { super('Konflikt'); } }
class Schlecht extends Error {}

export type Eintrag = { id: string; eltern: string; name: string; ordner: boolean; groesse: number; geaendert: string; fassung: string };
type Rec = Eintrag & { pfad: string; mtimeMs: number; tiefe: number };

const idVon = (s: BigIntStats) => `${s.dev.toString(36)}-${s.ino.toString(36)}-${s.birthtimeMs.toString(36)}`;
const ID_FORM = /^[0-9a-z]{1,20}-[0-9a-z]{1,20}-[0-9a-z]{1,20}$/;
const ANKER_FORM = /^([0-9a-f]{8})\.(\d{1,12})$/;

const oeffentlich = ({ pfad: _p, mtimeMs: _m, tiefe: _t, ...e }: Rec): Eintrag => e;

export class DateiSync {
  private stand = new Map<string, Rec>();
  private epoche = crypto.randomUUID().slice(0, 8); // nach einem Neustart des Dienstes neu: alte Anker sind 410, die App liest alles neu
  private n = 0;
  private log: { n: number; id: string }[] = [];
  private logAb = 0; // Anker ab dieser Nummer sind im Protokoll vollständig
  private gescannt = 0;

  // Tests setzen die Grenzen klein (Zeit, Protokoll, Einträge).
  constructor(private d: Dateien, private o: { frischMs?: number; maxLog?: number; maxEintraege?: number } = {}) {}

  // ---------- Lesen ----------

  private rec(s: BigIntStats, name: string, pfad: string, eltern: string): Rec {
    const ordner = s.isDirectory();
    const mtimeMs = Number(s.mtimeMs);
    const groesse = ordner ? 0 : Number(s.size);
    return { id: idVon(s), eltern, name, ordner, groesse, geaendert: new Date(mtimeMs).toISOString(), fassung: ordner ? String(mtimeMs) : `${mtimeMs}-${groesse}`, pfad, mtimeMs, tiefe: pfad.split('/').length };
  }

  private kinderVon(abs: string, rel: string, eltern: string): Rec[] {
    const aus: Rec[] = [];
    for (const name of readdirSync(abs)) {
      if (name.startsWith('.') || name.endsWith('.teil')) continue; // versteckt und halbe Uploads
      try {
        const s = lstatSync(join(abs, name), { bigint: true });
        if (s.isSymbolicLink() || !(s.isDirectory() || s.isFile())) continue; // Symlinks erscheinen hier nie (kein Ausbruch, keine Schleifen)
        aus.push(this.rec(s, name, rel ? `${rel}/${name}` : name, eltern));
      } catch { /* verschwunden */ }
    }
    return aus;
  }

  private scanne() {
    const neu = new Map<string, Rec>();
    const stapel = [{ abs: this.d.wurzel, rel: '', id: '' }];
    while (stapel.length) {
      const o = stapel.pop()!;
      for (const r of this.kinderVon(o.abs, o.rel, o.id)) {
        if (neu.size >= (this.o.maxEintraege ?? MAX_EINTRAEGE)) throw new Error('zu viele Einträge');
        neu.set(r.id, r);
        if (r.ordner) stapel.push({ abs: join(o.abs, r.name), rel: r.pfad, id: r.id });
      }
    }
    const geaendert: string[] = [];
    for (const [id, r] of neu) {
      const a = this.stand.get(id);
      // Ordner: nur Name und Ort zählen; ihre Zeit ändert sich bei jedem Kind und wäre Lärm
      if (!a || a.eltern !== r.eltern || a.name !== r.name || a.ordner !== r.ordner || (!r.ordner && (a.groesse !== r.groesse || a.mtimeMs !== r.mtimeMs))) geaendert.push(id);
    }
    for (const id of this.stand.keys()) if (!neu.has(id)) geaendert.push(id);
    if (geaendert.length) {
      this.n++;
      for (const id of geaendert) this.log.push({ n: this.n, id });
      const maxLog = this.o.maxLog ?? MAX_LOG;
      if (this.log.length > maxLog) {
        const weg = this.log.splice(0, this.log.length - maxLog);
        this.logAb = weg[weg.length - 1].n;
      }
    }
    this.stand = neu;
    this.gescannt = Date.now();
  }

  private frisch(erzwinge = false) { if (erzwinge || Date.now() - this.gescannt >= (this.o.frischMs ?? FRISCH_MS)) this.scanne(); }
  private veraltet() { this.gescannt = 0; }

  /** Eintrag zu einem relativen Pfad (Elternordner per realpath geprüft). Wirft Verboten, NichtDa. */
  private lies(rel: string): Rec {
    const { ordner, name } = this.d.neuesZiel(rel);
    let s: BigIntStats;
    try { s = lstatSync(join(ordner, name), { bigint: true }); } catch { throw new NichtDa(); }
    if (s.isSymbolicLink() || !(s.isDirectory() || s.isFile())) throw new NichtDa();
    const eltern = ordner === this.d.wurzel ? '' : idVon(lstatSync(ordner, { bigint: true }));
    return this.rec(s, name, relative(this.d.wurzel, join(ordner, name)), eltern);
  }

  /** Relativer Pfad zu einer Kennung ('' = Wurzel). Prüft, dass dort wirklich noch dieselbe Datei liegt; sonst einmal neu lesen, dann NichtDa. */
  private loese(id: string): string {
    if (id === '') return '';
    if (!ID_FORM.test(id)) throw new Schlecht();
    this.frisch();
    for (let versuch = 0; versuch < 2; versuch++) {
      const r = this.stand.get(id);
      if (r) { try { if (this.lies(r.pfad).id === id) return r.pfad; } catch (e) { if (e instanceof Verboten) throw e; } }
      if (versuch === 0) this.scanne();
    }
    throw new NichtDa();
  }

  private ordnerPfad(id: string): string {
    const rel = this.loese(id);
    if (rel !== '' && !statSync(this.d.aufloesen(rel)).isDirectory()) throw new Schlecht();
    return rel;
  }

  private fehler(e: unknown): Response {
    if (e instanceof Verboten) return leer(403);
    if (e instanceof NichtDa) return leer(404);
    if (e instanceof Schlecht) return leer(400);
    if (e instanceof Konflikt) return e.aktuell ? json(e.aktuell, 409) : leer(409);
    const code = (e as { code?: string })?.code;
    if (code === 'EEXIST' || code === 'ENOTEMPTY') return leer(409);
    if (code === 'ENOENT') return leer(404);
    if (code === 'ENOTDIR' || code === 'EISDIR') return leer(400);
    const r = ablegeFehler(e);
    if (r) return r;
    throw e;
  }

  private static name(n: unknown): string {
    if (typeof n !== 'string' || n === '' || n === '.' || n === '..' || n.includes('/') || n.includes('\0') || n.startsWith('.') || n.endsWith('.teil')) throw new Schlecht();
    if (new TextEncoder().encode(n).length > MAX_NAME_BYTES) throw new Schlecht();
    return n;
  }

  private async lieseJson(req: Request): Promise<Record<string, unknown>> {
    try {
      const v = JSON.parse(new TextDecoder().decode(await liesBegrenzt(req, 64 * 1024)));
      if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>;
    } catch { /* unten */ }
    throw new Schlecht();
  }

  private static idFeld(v: unknown, erlaubeLeer: boolean): string {
    if (typeof v !== 'string' || (v === '' && !erlaubeLeer)) throw new Schlecht();
    return v;
  }

  // ---------- Routen ----------

  // kurz: nur den aktuellen Anker (für `currentSyncAnchor` am Handy), ohne den Baum zu schicken
  aenderungen(anker: string | null, kurz = false): Response {
    try {
      this.frisch();
      const aktuell = `${this.epoche}.${this.n}`;
      if (kurz) return json({ anker: aktuell, voll: true, eintraege: [], weg: [] });
      if (anker === null) return json({ anker: aktuell, voll: true, eintraege: this.sortiert([...this.stand.values()]), weg: [] });
      const m = ANKER_FORM.exec(anker);
      if (!m || m[1] !== this.epoche) return leer(410);
      const k = Number(m[2]);
      if (k > this.n || k < this.logAb) return leer(410);
      const ids = new Set(this.log.filter(l => l.n > k).map(l => l.id));
      const eintraege: Rec[] = [], weg: string[] = [];
      for (const id of ids) { const r = this.stand.get(id); if (r) eintraege.push(r); else weg.push(id); }
      return json({ anker: aktuell, voll: false, eintraege: this.sortiert(eintraege), weg });
    } catch (e) { return this.fehler(e); }
  }

  private sortiert(l: Rec[]): Eintrag[] { return l.sort((a, b) => a.tiefe - b.tiefe || a.pfad.localeCompare(b.pfad)).map(oeffentlich); }

  kinder(id: string | null): Response {
    try {
      const rel = this.ordnerPfad(id ?? '');
      const eltern = rel === '' ? '' : this.lies(rel).id;
      const l = this.kinderVon(this.d.aufloesen(rel), rel, eltern);
      l.sort((a, b) => Number(b.ordner) - Number(a.ordner) || a.name.localeCompare(b.name));
      return json(l.map(oeffentlich));
    } catch (e) { return this.fehler(e); }
  }

  eintrag(id: string | null): Response {
    try {
      if (!id) return leer(400);
      const r = this.lies(this.loese(id));
      return json({ ...oeffentlich(r), pfad: r.pfad });
    } catch (e) { return this.fehler(e); }
  }

  /** Neue Datei in einem Ordner (Kennung), nie überschreiben (` (2)`): derselbe Weg wie `PUT /v1/datei`, Antwort mit Eintrag. */
  async neu(req: Request, dateien: Dateien, eltern: string | null, name: string | null): Promise<Response> {
    let rel: string, n: string;
    try { rel = this.ordnerPfad(eltern ?? ''); n = DateiSync.name(name); } catch (e) { return this.fehler(e); }
    const antwort = await dateien.hochladen(req, rel ? `${rel}/${n}` : n);
    if (antwort.status !== 200) return antwort;
    try {
      const abgelegt = (await antwort.json() as { name: string }).name;
      this.veraltet();
      return json(oeffentlich(this.lies(rel ? `${rel}/${abgelegt}` : abgelegt)));
    } catch (e) { return this.fehler(e); }
  }

  async ordner(req: Request): Promise<Response> {
    try {
      const b = await this.lieseJson(req);
      const rel = this.ordnerPfad(DateiSync.idFeld(b.eltern, true));
      const name = DateiSync.name(b.name);
      const eltern = this.d.aufloesen(rel);
      mkdirSync(join(eltern, name), { mode: 0o700 }); // EEXIST = 409
      this.veraltet();
      return json(oeffentlich(this.lies(rel ? `${rel}/${name}` : name)));
    } catch (e) { return this.fehler(e); }
  }

  async umbenennen(req: Request): Promise<Response> {
    try {
      const b = await this.lieseJson(req);
      const alt = this.loese(DateiSync.idFeld(b.id, false));
      if (GESCHUETZT.has(alt)) throw new Verboten();
      const { ordner: altOrdner, name: altName } = this.d.neuesZiel(alt);
      const neuerOrdner = b.eltern === undefined ? altOrdner : this.d.aufloesen(this.ordnerPfad(DateiSync.idFeld(b.eltern, true)));
      const neuerName = b.name === undefined ? altName : DateiSync.name(b.name);
      const von = join(altOrdner, altName), nach = join(neuerOrdner, neuerName);
      if (von !== nach) {
        try { lstatSync(nach); throw new Konflikt(); } catch (e) { if (e instanceof Konflikt) throw e; } // nie überschreiben
        renameSync(von, nach); // EINVAL (Ordner in sich selbst) wird 400
      }
      this.veraltet();
      return json(oeffentlich(this.lies(relative(this.d.wurzel, nach))));
    } catch (e) { return this.fehler(e); }
  }

  async ersetzen(req: Request, id: string | null, fassung: string | null): Promise<Response> {
    let temp = '', alt = '';
    try {
      if (!id || !fassung) return leer(400);
      const rel = this.loese(id);
      const jetzt = this.lies(rel);
      if (jetzt.ordner) return leer(400);
      if (jetzt.fassung !== fassung) throw new Konflikt(oeffentlich(jetzt)); // PC hat die Datei inzwischen geändert: nichts überschreiben
      const abgelehnt = pruefeUpload(req, this.d.wurzel, this.d.mindestFrei);
      if (abgelehnt) return abgelehnt;
      const { ordner, name } = this.d.neuesZiel(rel);
      temp = join(ordner, `.heimherz-${crypto.randomUUID()}.teil`);
      try { await streameInDatei(req, temp); } catch (e) { return ablegeFehler(e) ?? leer(400); }
      const nochmal = this.lies(rel);
      if (nochmal.id !== id || nochmal.fassung !== fassung) throw new Konflikt(oeffentlich(nochmal)); // während des Uploads geändert
      // In dieselbe Datei schreiben (Inode und damit die Kennung bleiben). Vorher Kopie: scheitert das Schreiben, kommt die alte Fassung zurück; stürzt der Rechner ab, bleibt sie als versteckte .alt-Datei liegen.
      const ziel = join(ordner, name);
      alt = join(ordner, `.heimherz-${crypto.randomUUID()}.alt`);
      copyFileSync(ziel, alt);
      try { copyFileSync(temp, ziel); } catch (e) { copyFileSync(alt, ziel); throw e; }
      this.veraltet();
      return json(oeffentlich(this.lies(rel)));
    } catch (e) { return this.fehler(e); } finally { if (temp) loescheLeise(temp); if (alt) loescheLeise(alt); }
  }

  async papierkorb(req: Request): Promise<Response> {
    try {
      const b = await this.lieseJson(req);
      const rel = this.loese(DateiSync.idFeld(b.id, false));
      if (GESCHUETZT.has(rel)) throw new Verboten();
      if (b.fassung !== undefined) {
        const jetzt = this.lies(rel);
        if (b.fassung !== jetzt.fassung) throw new Konflikt(oeffentlich(jetzt));
      }
      const r = await this.d.nachPapierkorb(rel);
      this.veraltet();
      return r;
    } catch (e) { return this.fehler(e); }
  }
}
