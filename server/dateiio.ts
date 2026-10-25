import { linkSync, mkdirSync, statfsSync, unlinkSync } from 'node:fs';
import { open } from 'node:fs/promises';
import { join, parse } from 'node:path';
import { leer } from './http';

export const MINDEST_FREI = 5 * 1024 ** 3;

// Vor jedem Upload: unter `mindest` freiem Platz 507; mit `laengePflicht` ohne Content-Length 411. null = weiter.
// Fotos dürfen chunked kommen: ob Apples Upload-Jobs die Länge senden, ist nicht belegt; Bun bricht Chunked ohne Endblock ab.
export function pruefeUpload(req: Request, ordner: string, mindest: number, laengePflicht = true): Response | null {
  if (laengePflicht && req.headers.get('content-length') === null) return leer(411);
  const s = statfsSync(ordner);
  return s.bavail * s.bsize < mindest ? leer(507) : null;
}

// Fehler beim Ablegen, die der Absender oder die Platte verschuldet (kein Stacktrace, kein 500): Platte voll 507, unmöglicher Name 400.
const ABLEGE_STATUS: Record<string, number> = { ENOSPC: 507, EDQUOT: 507, ENAMETOOLONG: 400, EILSEQ: 400, EINVAL: 400 };
export const ablegeFehler = (e: unknown): Response | null => {
  const status = ABLEGE_STATUS[(e as { code?: string })?.code ?? ''];
  return status ? leer(status) : null;
};

// Body Stück für Stück auf die Platte (nie ganz im Speicher). Stimmt Content-Length nicht, war der Upload unvollständig.
export async function streameInDatei(req: Request, pfad: string): Promise<number> {
  const fh = await open(pfad, 'wx', 0o600);
  let n = 0;
  try {
    if (req.body) for await (const t of req.body as any as AsyncIterable<Uint8Array>) { await fh.write(t); n += t.length; }
    const cl = req.headers.get('content-length');
    if (cl !== null && Number(cl) !== n) throw new Error('Upload unvollständig');
  } finally { await fh.close(); }
  return n;
}

// Legt temp unter einem freien Namen in ordner ab, überschreibt nie (link schlägt bei vorhandenem Namen fehl): "name (2).ext".
export function legeOhneUeberschreibenAb(temp: string, ordner: string, name: string): string {
  mkdirSync(ordner, { recursive: true, mode: 0o700 });
  const { name: basis, ext } = parse(name);
  for (let i = 1; ; i++) {
    const ziel = join(ordner, i === 1 ? name : `${basis} (${i})${ext}`);
    try { linkSync(temp, ziel); unlinkSync(temp); return ziel; } catch (e: any) { if (e.code !== 'EEXIST') throw e; }
  }
}

export const loescheLeise = (p: string) => { try { unlinkSync(p); } catch { /* war nie da */ } };
