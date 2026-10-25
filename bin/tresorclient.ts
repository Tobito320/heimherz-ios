// Das CLI ist ein Gerät: holt den Umschlag, öffnet ihn mit K, ändert, verschließt, PUT mit If-Match (SPEC 7).
import { oeffne, schluessel, verschliesse, type Umschlag } from '../lib/umschlag';
import type { Tresor } from '../lib/zusammenfuehren';

export type Verbindung = { url: string; token: string };

export const leererTresor = (): Tresor => ({ format: 1, eintraege: [] });

export class DienstFehler extends Error {}

async function anfrage(v: Verbindung, pfad: string, init: RequestInit = {}): Promise<Response> {
  try {
    return await fetch(v.url + pfad, { ...init, headers: { authorization: `Bearer ${v.token}`, ...(init.headers as object) } });
  } catch { throw new DienstFehler('Dienst nicht erreichbar (läuft heimherz.service?)'); }
}

export async function holeStatus(v: Verbindung) {
  const r = await anfrage(v, '/v1/status');
  if (!r.ok) throw new DienstFehler(`Dienst antwortet mit ${r.status}`);
  return await r.json() as { version: string; rev: number; fotos: number; belegt: number; frei: number };
}

async function holeUmschlag(v: Verbindung): Promise<Umschlag | null> {
  const r = await anfrage(v, '/v1/tresor');
  if (r.status === 404) return null;
  if (!r.ok) throw new DienstFehler(`Tresor holen: ${r.status}`);
  return await r.json() as Umschlag;
}

export async function ladeTresor(v: Verbindung, k: Uint8Array): Promise<{ tresor: Tresor; rev: number }> {
  const u = await holeUmschlag(v);
  return u ? { tresor: await oeffne<Tresor>(u, await schluessel(k)), rev: u.rev } : { tresor: leererTresor(), rev: 0 };
}

// aendere bekommt den aktuellen Tresor und liefert den neuen (oder null = nichts zu tun). Bei 409 neu holen, höchstens `versuche` Mal.
export async function aendereTresor(v: Verbindung, k: Uint8Array, aendere: (t: Tresor) => Tresor | null | Promise<Tresor | null>, versuche = 3): Promise<{ rev: number; geschrieben: boolean }> {
  const key = await schluessel(k);
  let aktuell = await holeUmschlag(v);
  for (let i = 0; i < versuche; i++) {
    const alt = aktuell ? await oeffne<Tresor>(aktuell, key) : leererTresor();
    const neu = await aendere(alt);
    if (!neu || JSON.stringify(neu) === JSON.stringify(alt)) return { rev: aktuell?.rev ?? 0, geschrieben: false };
    const r = await anfrage(v, '/v1/tresor', { method: 'PUT', headers: { 'if-match': String(aktuell?.rev ?? 0) }, body: JSON.stringify(await verschliesse(neu, key)) });
    if (r.ok) return { rev: (await r.json() as Umschlag).rev, geschrieben: true };
    if (r.status !== 409) throw new DienstFehler(`Tresor speichern: ${r.status}`);
    aktuell = await holeUmschlag(v); // die 409-Antwort hätte ihn auch, so ist es für 404 und Rennen gleich
  }
  throw new DienstFehler('Tresor wurde zu oft gleichzeitig geändert, bitte nochmal');
}
