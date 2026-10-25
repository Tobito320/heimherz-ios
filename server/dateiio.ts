import { linkSync, mkdirSync, unlinkSync } from 'node:fs';
import { open } from 'node:fs/promises';
import { join, parse } from 'node:path';

// Body Stück für Stück auf die Platte (nie ganz im Speicher). Stimmt Content-Length nicht, war der Upload unvollständig.
export async function streameInDatei(req: Request, pfad: string): Promise<number> {
  const fh = await open(pfad, 'wx', 0o644);
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
  mkdirSync(ordner, { recursive: true });
  const { name: basis, ext } = parse(name);
  for (let i = 1; ; i++) {
    const ziel = join(ordner, i === 1 ? name : `${basis} (${i})${ext}`);
    try { linkSync(temp, ziel); unlinkSync(temp); return ziel; } catch (e: any) { if (e.code !== 'EEXIST') throw e; }
  }
}

export const loescheLeise = (p: string) => { try { unlinkSync(p); } catch { /* war nie da */ } };
