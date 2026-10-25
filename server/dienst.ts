// Heimherz-Dienst am PC (SPEC 6). Nur Loopback; nach außen macht das `tailscale serve`.
import { Dateien } from './dateien';
import { Fotos } from './fotos';
import { Geraete } from './geraete';
import { json, leer } from './http';
import { Tresor } from './tresor';

export const VERSION = '0.1.0';

export type Optionen = {
  port: number; daten: string; fotos: string; dateien: string;
  papierkorb?: string[]; verlaufMax?: number;
};

export const istLoopback = (adresse: string | undefined) => !!adresse && ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(adresse);

export function starte(o: Optionen) {
  const geraete = new Geraete(o.daten);
  const tresor = new Tresor(o.daten, o.verlaufMax);
  const fotos = new Fotos(o.fotos, o.daten);
  const dateien = new Dateien(o.dateien, o.papierkorb ?? ['trash-put']);

  async function route(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const p = url.pathname, m = req.method;
    const pfad = url.searchParams.get('pfad');

    if (p === '/v1/status' && m === 'GET') return json({ version: VERSION, rev: tresor.rev(), fotos: fotos.anzahl(), ...fotos.speicher() });
    if (p === '/v1/tresor') {
      if (m === 'GET') return tresor.holen();
      if (m === 'PUT') return tresor.speichern(req);
    }
    if (p === '/v1/fotos/bekannt' && m === 'GET') return fotos.bekannt();
    const f = /^\/v1\/fotos\/([^/]+)\/([^/]+)$/.exec(p);
    if (f && m === 'PUT') return fotos.empfange(req, f[1], f[2]);
    if (p === '/v1/dateien' && m === 'GET') return dateien.liste(pfad);
    if (p === '/v1/datei') {
      if (m === 'GET') return dateien.herunterladen(pfad, req.headers.get('range'));
      if (m === 'PUT') return dateien.hochladen(req, pfad);
    }
    if (p === '/v1/datei/papierkorb' && m === 'POST') return dateien.inPapierkorb(req);
    return leer(404);
  }

  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: o.port,
    maxRequestBodySize: Number.MAX_SAFE_INTEGER, // Videos: Grenzen setzen wir selbst (Tresor 20 MB), alles andere läuft gestreamt
    idleTimeout: 120,
    async fetch(req, srv) {
      if (!istLoopback(srv.requestIP(req)?.address)) return leer(403);
      const token = /^Bearer (\S+)$/.exec(req.headers.get('authorization') ?? '')?.[1] ?? null;
      if (!geraete.pruefe(token)) return leer(401);
      try { return await route(req); } catch (e) {
        console.error('Fehler:', req.method, new URL(req.url).pathname, (e as Error)?.message);
        return leer(500);
      }
    },
  });
  return server;
}
