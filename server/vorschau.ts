// Vorschaubilder für die Dateien-App (SPEC 6): Bild, erste PDF-Seite oder ein Videobild als kleines JPEG, einmal erzeugt und im Datenordner gemerkt.
// Programme laufen mit Argumentliste (nie über eine Shell); die Quelle geht über stdin bzw. nach `--` oder als absoluter Pfad mit `file:`.
import { chmodSync, mkdirSync, readFileSync, renameSync, rmSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';

export type Art = 'bild' | 'pdf' | 'video';
export type Auftrag = { art: Art; quelle: string; endung: string; ziel: string; px: number; qualitaet: number };
export type Erzeuger = (a: Auftrag) => Promise<void>;
export type VorschauOptionen = { erzeuger?: Erzeuger; zeitlimitMs?: number };

export const MAX_BYTES = 300 * 1024;
const PARALLEL = 2;
const QUALITAETEN = [80, 55, 35];

const BILD = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'tif', 'tiff', 'bmp']);
const VIDEO = new Set(['mp4', 'mov', 'm4v', 'mkv', 'avi', 'webm']);
export function artVon(name: string): { art: Art; endung: string } | null {
  const endung = extname(name).slice(1).toLowerCase();
  const art = endung === 'pdf' ? 'pdf' : BILD.has(endung) ? 'bild' : VIDEO.has(endung) ? 'video' : null;
  return art ? { art, endung } : null;
}

// Beendet den Prozess nach `zeitlimitMs`. Wirft bei Zeitüberschreitung, Fehlercode oder fehlendem Programm.
export async function fuehreAus(argv: string[], zeitlimitMs: number, stdin: Blob | 'ignore' = 'ignore'): Promise<void> {
  const p = Bun.spawn(argv, { stdin: stdin === 'ignore' ? 'ignore' : stdin, stdout: 'ignore', stderr: 'ignore' });
  let zuSpaet = false;
  const uhr = setTimeout(() => { zuSpaet = true; p.kill('SIGKILL'); }, zeitlimitMs);
  try {
    const code = await p.exited;
    if (zuSpaet) throw new Error('Zeitlimit');
    if (code !== 0) throw new Error(`${argv[0]} Code ${code}`);
  } finally { clearTimeout(uhr); }
}

// magick liest aus stdin mit ausdrücklichem Format: kein Dateiname wird als Option, Muster oder Bildbereich gedeutet, Inhalt, der nicht zum Format passt, scheitert.
export const MAGICK_FORMAT: Record<string, string> = { jpg: 'jpeg', jpeg: 'jpeg', png: 'png', gif: 'gif', webp: 'webp', heic: 'heic', heif: 'heif', tif: 'tiff', tiff: 'tiff', bmp: 'bmp' };

export const echterErzeuger = (zeitlimitMs = 10_000): Erzeuger => async ({ art, quelle, endung, ziel, px, qualitaet }) => {
  if (art === 'bild') {
    await fuehreAus(['magick', '-limit', 'memory', '256MiB', '-limit', 'map', '512MiB', '-limit', 'disk', '1GiB', '-limit', 'time', '10', '-define', `jpeg:size=${px * 2}x${px * 2}`,
      `${MAGICK_FORMAT[endung]}:-[0]`, '-auto-orient', '-thumbnail', `${px}x${px}>`, '-background', 'white', '-alpha', 'remove', '-alpha', 'off',
      '-strip', '-interlace', 'Plane', '-quality', String(qualitaet), `jpeg:${ziel}`], zeitlimitMs, Bun.file(quelle));
  } else if (art === 'pdf') {
    // pdftoppm hängt die Endung selbst an: Ziel ohne ".jpg" übergeben
    await fuehreAus(['pdftoppm', '-jpeg', '-jpegopt', `quality=${qualitaet}`, '-f', '1', '-l', '1', '-scale-to', String(px), '-singlefile', '--', quelle, ziel.replace(/\.jpg$/, '')], zeitlimitMs);
  } else {
    const q = String(Math.max(2, Math.round((100 - qualitaet) / 3.3)));
    const lauf = (ab: string) => fuehreAus(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', '-ss', ab, '-i', `file:${quelle}`, '-frames:v', '1', '-an', '-sn',
      '-vf', `scale=w=${px}:h=${px}:force_original_aspect_ratio=decrease`, '-pix_fmt', 'yuvj420p', '-q:v', q, '-f', 'image2', '-c:v', 'mjpeg', ziel], zeitlimitMs);
    // Video kürzer als eine Sekunde: ffmpeg endet mit Code 0 ohne Bild; dann das erste Bild
    const hatBild = () => { try { return statSync(ziel).size > 0; } catch { return false; } };
    try { await lauf('1'); } catch { /* weiter mit 0 */ }
    if (!hatBild()) await lauf('0');
  }
};

export class Vorschauen {
  private erzeuger: Erzeuger;
  private laufend = new Map<string, Promise<Uint8Array | null>>();
  private misslungen = new Set<string>(); // shortcut: nur bis zum Neustart gemerkt, nicht auf der Platte; nötig nur, wenn kaputte Dateien dauernd neu versucht werden
  private frei = PARALLEL;
  private warte: (() => void)[] = [];

  // shortcut: der Cache wird nie aufgeräumt (ein Bild je Datei, Größe und px, meist unter 100 KB); bei Platzmangel Ordner `vorschau/` einfach löschen
  constructor(private ordner: string, o: VorschauOptionen = {}) {
    this.erzeuger = o.erzeuger ?? echterErzeuger(o.zeitlimitMs);
    mkdirSync(ordner, { recursive: true, mode: 0o700 });
    chmodSync(ordner, 0o700);
  }

  async hole(quelle: string, art: Art, endung: string, s: { size: number; mtimeMs: number }, px: number): Promise<Uint8Array | null> {
    const schluessel = new Bun.CryptoHasher('sha256').update(`${quelle}\0${s.size}\0${s.mtimeMs}\0${px}`).digest('hex');
    const ziel = join(this.ordner, `${schluessel}.jpg`);
    try { return new Uint8Array(readFileSync(ziel)); } catch { /* noch nicht da */ }
    if (this.misslungen.has(schluessel)) return null;
    let l = this.laufend.get(schluessel);
    if (!l) {
      l = this.erzeuge({ art, quelle, endung, px }, schluessel, ziel).finally(() => this.laufend.delete(schluessel));
      this.laufend.set(schluessel, l);
    }
    return l;
  }

  private async platz() {
    if (this.frei > 0) { this.frei--; return; }
    await new Promise<void>(r => this.warte.push(r));
  }
  private gib() { const n = this.warte.shift(); if (n) n(); else this.frei++; }

  private async erzeuge(a: Omit<Auftrag, 'ziel' | 'qualitaet'>, schluessel: string, ziel: string): Promise<Uint8Array | null> {
    await this.platz();
    const temp = join(this.ordner, `.${schluessel}-${crypto.randomUUID()}.jpg`);
    try {
      for (const qualitaet of QUALITAETEN) {
        await this.erzeuger({ ...a, ziel: temp, qualitaet });
        const n = statSync(temp).size;
        if (n === 0) break;
        if (n <= MAX_BYTES) {
          chmodSync(temp, 0o600);
          renameSync(temp, ziel);
          return new Uint8Array(readFileSync(ziel));
        }
      }
    } catch { /* Programm fehlt, Zeitlimit, kaputte Datei: kein Bild */ } finally {
      rmSync(temp, { force: true });
      this.gib();
    }
    this.misslungen.add(schluessel);
    return null;
  }
}
