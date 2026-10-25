// Dateien am PC (SPEC 6): nur unterhalb von HEIMHERZ_DATEIEN, nie Symlinks hinaus, nie überschreiben, löschen nur in den Papierkorb.
import { lstatSync, mkdirSync, readdirSync, realpathSync, statSync } from 'node:fs';
import { basename, join, sep } from 'node:path';
import { json, leer, liesBegrenzt } from './http';
import { legeOhneUeberschreibenAb, loescheLeise, streameInDatei } from './dateiio';

class Verboten extends Error {}
class NichtDa extends Error {}

export class Dateien {
  private wurzel: string;

  constructor(ordner: string, private papierkorb: string[]) {
    mkdirSync(ordner, { recursive: true });
    this.wurzel = realpathSync(ordner);
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
          ausgabe.push({ name, ordner: s.isDirectory(), groesse: s.isDirectory() ? 0 : s.size, geaendert: s.mtime.toISOString() });
        } catch { /* kaputter Symlink */ }
      }
      ausgabe.sort((a, b) => Number(b.ordner) - Number(a.ordner) || a.name.localeCompare(b.name));
      return json(ausgabe);
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
    try { ziel = this.neuesZiel(pfad); } catch (e) { return this.fehler(e); }
    if (ziel.name.startsWith('.heimherz-')) return leer(400);
    const temp = join(ziel.ordner, `.heimherz-${crypto.randomUUID()}.teil`);
    try {
      try { await streameInDatei(req, temp); } catch { return leer(400); }
      const fertig = legeOhneUeberschreibenAb(temp, ziel.ordner, ziel.name);
      return json({ name: basename(fertig) });
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
