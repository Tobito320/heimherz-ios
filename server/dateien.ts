// Dateien am PC (SPEC 6): nur unterhalb von HEIMHERZ_DATEIEN, nie Symlinks hinaus, nie überschreiben, löschen nur in den Papierkorb.
import { lstatSync, mkdirSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { basename, join, sep } from 'node:path';
import { json, leer, liesBegrenzt } from './http';
import { artVon, Vorschauen, type VorschauOptionen } from './vorschau';
import { ablegeFehler, legeOhneUeberschreibenAb, loescheLeise, MINDEST_FREI, pruefeUpload, streameInDatei } from './dateiio';

const MAX_TREFFER = 200;
const MAX_SUCHE = 200;
const MAX_BESUCHT = 200_000;

// Groß/klein und Umlaute egal: ä = ae, ö = oe, ü = ue, ß = ss; zerlegte Zeichen (Mac) zuerst zusammensetzen.
export const normalisiere = (s: string) => s.normalize('NFC').toLowerCase().replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');

class Verboten extends Error {}
class NichtDa extends Error {}

export class Dateien {
  private wurzel: string;

  private vorschauen: Vorschauen;

  constructor(ordner: string, private papierkorb: string[], private mindestFrei = MINDEST_FREI, vorschauOrdner = join(ordner, '..', 'vorschau'), vorschau?: VorschauOptionen) {
    mkdirSync(ordner, { recursive: true, mode: 0o700 });
    this.wurzel = realpathSync(ordner);
    this.vorschauen = new Vorschauen(vorschauOrdner, vorschau);
  }

  private innen(p: string) { return p === this.wurzel || p.startsWith(this.wurzel + sep); }

  // Relativer Pfad -> absoluter Pfad. Wirft Verboten bei "..", absolut, NUL; die Symlink-Prüfung macht der Aufrufer per realpath.
  private teile(pfad: string | null): string[] {
    const p = pfad ?? '';
    if (p.includes('\0') || p.startsWith('/')) throw new Verboten();
    const t = p.split('/').filter(s => s !== '' && s !== '.');
    if (t.includes('..')) throw new Verboten();
    return t;
  }

  private aufloesen(pfad: string | null): string {
    const ziel = join(this.wurzel, ...this.teile(pfad));
    let echt: string;
    try { echt = realpathSync(ziel); } catch { throw new NichtDa(); }
    if (!this.innen(echt)) throw new Verboten();
    return echt;
  }

  // Ziel muss nicht existieren, der Elternordner schon und echt innerhalb liegen.
  private neuesZiel(pfad: string | null): { ordner: string; name: string } {
    const t = this.teile(pfad);
    const name = t.pop();
    if (!name) throw new Verboten();
    const ordner = this.aufloesen(t.join('/'));
    if (!statSync(ordner).isDirectory()) throw new NichtDa();
    return { ordner, name };
  }

  // Nur unter "Eingang/" legt ein Upload fehlende Ordner an (Handy-Ordner kommen mit Unterordnern); sonst bleibt es bei 404.
  // Schritt für Schritt, damit ein Symlink nach draußen nie zum Anlegen außerhalb führt (Verboten).
  private legeEingangAn(pfad: string | null) {
    const t = this.teile(pfad);
    if (t.length < 2 || t[0] !== 'Eingang') return;
    let akt = this.wurzel;
    for (const s of t.slice(0, -1)) {
      const ziel = join(akt, s);
      let vorhanden = true;
      try { lstatSync(ziel); } catch { vorhanden = false; }
      if (!vorhanden) { mkdirSync(ziel, { mode: 0o700 }); akt = ziel; continue; }
      akt = realpathSync(ziel);
      if (!this.innen(akt)) throw new Verboten();
    }
  }

  private fehler(e: unknown): Response {
    if (e instanceof Verboten) return leer(403);
    if (e instanceof NichtDa) return leer(404);
    throw e;
  }

  liste(pfad: string | null): Response {
    try {
      const ordner = this.aufloesen(pfad);
      if (!statSync(ordner).isDirectory()) return leer(400);
      const ausgabe = [];
      for (const name of readdirSync(ordner)) {
        if (name.startsWith('.heimherz-')) continue; // eigene Temp-Dateien
        const p = join(ordner, name);
        try {
          if (!this.innen(realpathSync(p))) continue; // Symlink nach draußen: unsichtbar
          const s = statSync(p);
          ausgabe.push({ name, ordner: s.isDirectory(), groesse: s.isDirectory() ? 0 : s.size, geaendert: s.mtime.toISOString(), ...(s.isDirectory() ? { anzahl: this.zaehle(p) } : {}) });
        } catch { /* kaputter Symlink */ }
      }
      ausgabe.sort((a, b) => Number(b.ordner) - Number(a.ordner) || a.name.localeCompare(b.name));
      return json(ausgabe);
    } catch (e) { return this.fehler(e); }
  }

  // Einträge eines Ordners für "12 Objekte"; unlesbar = 0.
  private zaehle(ordner: string): number {
    try { return readdirSync(ordner).filter(n => !n.startsWith('.heimherz-')).length; } catch { return 0; }
  }

  // Suche im Namen, rekursiv ab pfad. Symlinks erscheinen als Treffer, werden aber nie betreten (keine Schleifen, kein Ausbruch).
  suche(q: string | null, pfad: string | null): Response {
    const woerter = normalisiere(q ?? '').split(/\s+/).filter(Boolean);
    if (woerter.length === 0 || (q ?? '').length > MAX_SUCHE) return leer(400);
    try {
      const start = this.aufloesen(pfad);
      if (!statSync(start).isDirectory()) return leer(400);
      const treffer: { pfad: string; name: string; ordner: boolean; groesse: number; geaendert: string; rang: number; zeit: number }[] = [];
      const stapel: { echt: string; teile: string[] }[] = [{ echt: start, teile: this.teile(pfad) }];
      let besucht = 0; // shortcut: nach 200.000 Einträgen Schluss; bei Millionen Dateien Index statt Durchlauf
      while (stapel.length && besucht < MAX_BESUCHT) {
        const { echt, teile } = stapel.pop()!;
        let eintraege;
        try { eintraege = readdirSync(echt, { withFileTypes: true }); } catch { continue; }
        for (const e of eintraege) {
          besucht++;
          if (e.name.startsWith('.') || e.name.endsWith('.teil')) continue; // versteckt und halbe Uploads (.teil)
          const p = join(echt, e.name);
          let tief = e.isDirectory();
          try {
            if (e.isSymbolicLink()) { if (!this.innen(realpathSync(p))) continue; tief = false; }
            else if (!tief && !e.isFile()) continue;
            if (tief) stapel.push({ echt: p, teile: [...teile, e.name] });
            const n = normalisiere(e.name);
            if (!woerter.every(w => n.includes(w))) continue;
            const s = statSync(p);
            treffer.push({ pfad: [...teile, e.name].join('/'), name: e.name, ordner: s.isDirectory(), groesse: s.isDirectory() ? 0 : s.size,
              geaendert: s.mtime.toISOString(), rang: n.startsWith(woerter[0]) ? 0 : 1, zeit: s.mtimeMs });
          } catch { /* kaputter Symlink, verschwunden */ }
        }
      }
      treffer.sort((a, b) => Number(b.ordner) - Number(a.ordner) || a.rang - b.rang || b.zeit - a.zeit || a.pfad.localeCompare(b.pfad));
      return json(treffer.slice(0, MAX_TREFFER).map(({ rang: _r, zeit: _z, ...t }) => t));
    } catch (e) { return this.fehler(e); }
  }

  async vorschau(pfad: string | null, pxText: string | null): Promise<Response> {
    try {
      const p = this.aufloesen(pfad);
      const s = statSync(p);
      if (!s.isFile()) return leer(400);
      const name = basename(p);
      const art = name.startsWith('.heimherz-') ? null : artVon(name);
      if (!art) return leer(404);
      const px = pxText === null ? 240 : /^\d{1,4}$/.test(pxText) ? Number(pxText) : NaN;
      if (!(px >= 120 && px <= 600)) return leer(400);
      const bild = await this.vorschauen.hole(p, art.art, art.endung, s, px);
      if (!bild) return leer(404);
      return new Response(bild, { headers: { 'content-type': 'image/jpeg', 'cache-control': 'private, max-age=86400', 'x-content-type-options': 'nosniff' } });
    } catch (e) { return this.fehler(e); }
  }

  herunterladen(pfad: string | null, range: string | null): Response {
    try {
      const p = this.aufloesen(pfad);
      const s = statSync(p);
      if (!s.isFile()) return leer(400);
      const datei = Bun.file(p);
      const kopf = { 'accept-ranges': 'bytes', 'content-type': datei.type };
      const m = range ? /^bytes=(\d*)-(\d*)$/.exec(range.trim()) : null;
      if (!m || (m[1] === '' && m[2] === '')) return new Response(datei, { headers: kopf });
      let von: number, bis: number;
      if (m[1] === '') { von = Math.max(0, s.size - Number(m[2])); bis = s.size - 1; } // "-n": die letzten n Bytes
      else { von = Number(m[1]); bis = m[2] === '' ? s.size - 1 : Math.min(Number(m[2]), s.size - 1); }
      if (von >= s.size || von > bis) return new Response(null, { status: 416, headers: { 'content-range': `bytes */${s.size}` } });
      return new Response(datei.slice(von, bis + 1), { status: 206, headers: { ...kopf, 'content-range': `bytes ${von}-${bis}/${s.size}`, 'content-length': String(bis - von + 1) } });
    } catch (e) { return this.fehler(e); }
  }

  async hochladen(req: Request, pfad: string | null): Promise<Response> {
    let ziel: { ordner: string; name: string };
    try { this.legeEingangAn(pfad); ziel = this.neuesZiel(pfad); } catch (e) { return this.fehler(e); }
    if (ziel.name.startsWith('.heimherz-')) return leer(400);
    const abgelehnt = pruefeUpload(req, this.wurzel, this.mindestFrei);
    if (abgelehnt) return abgelehnt;
    const temp = join(ziel.ordner, `.heimherz-${crypto.randomUUID()}.teil`);
    try {
      try { await streameInDatei(req, temp); } catch (e) { return ablegeFehler(e) ?? leer(400); }
      try { return json({ name: basename(legeOhneUeberschreibenAb(temp, ziel.ordner, ziel.name)) }); } catch (e) {
        const r = ablegeFehler(e);
        if (r) return r;
        throw e;
      }
    } finally { loescheLeise(temp); }
  }

  async inPapierkorb(req: Request): Promise<Response> {
    let pfad: unknown;
    try { pfad = JSON.parse(new TextDecoder().decode(await liesBegrenzt(req, 64 * 1024))).pfad; } catch { return leer(400); }
    if (typeof pfad !== 'string') return leer(400);
    try {
      const { ordner, name } = this.neuesZiel(pfad);
      const ziel = join(ordner, name);
      try { lstatSync(ziel); } catch { return leer(404); } // ein Symlink selbst darf in den Papierkorb, sein Ziel bleibt unberührt
      try {
        const p = Bun.spawn([...this.papierkorb, ziel], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' });
        return leer(await p.exited === 0 ? 200 : 500);
      } catch { return leer(500); } // Papierkorb-Befehl fehlt
    } catch (e) { return this.fehler(e); }
  }
}
