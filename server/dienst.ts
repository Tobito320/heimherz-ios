// Heimherz-Dienst am PC (SPEC 6). Nur Loopback; nach außen macht das `tailscale serve`.
import { join } from 'node:path';
import { Dateien } from './dateien';
import { DateiSync } from './dateisync';
import { Fotos } from './fotos';
import { Geraete } from './geraete';
import { json, leer } from './http';
import { Symbole, type SymbolOptionen } from './symbol';
import type { VorschauOptionen } from './vorschau';
import { Tresor } from './tresor';
import { Wiederherstellung } from './wiederherstellung';

export const VERSION = '0.1.0';

export type Optionen = {
  port: number; daten: string; fotos: string; dateien: string;
  papierkorb?: string[]; verlaufMax?: number; mindestFrei?: number;
  symbole?: SymbolOptionen; // Tests: Auflöser und Holer austauschen
  vorschau?: VorschauOptionen; // Tests: Erzeuger austauschen (kein echtes magick nötig)
  sync?: { frischMs?: number; maxLog?: number; maxEintraege?: number }; // Tests: Dateien-Sync mit kleinen Grenzen
};

const FOTO_OPTIONS = /^\/v1\/fotos\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9_-]{1,128})$/;

export const istLoopback = (adresse: string | undefined) => !!adresse && ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(adresse);

export function starte(o: Optionen) {
  const geraete = new Geraete(o.daten);
  const tresor = new Tresor(o.daten, o.verlaufMax);
  const wiederherstellung = new Wiederherstellung(o.daten);
  const fotos = new Fotos(o.fotos, o.daten, o.mindestFrei);
  const symbole = new Symbole(o.daten, o.symbole);
  const dateien = new Dateien(o.dateien, o.papierkorb ?? ['trash-put'], o.mindestFrei, join(o.daten, 'vorschau'), o.vorschau);

  const sync = new DateiSync(dateien, o.sync);

  async function route(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const p = url.pathname, m = req.method;
    const pfad = url.searchParams.get('pfad');

    if (p === '/v1/status' && m === 'GET') return json({ version: VERSION, rev: tresor.rev(), fotos: fotos.anzahl(), ...fotos.speicher() });
    if (p === '/v1/tresor') {
      if (m === 'GET') return tresor.holen();
      if (m === 'PUT') return tresor.speichern(req);
    }
    if (p === '/v1/wiederherstellung') {
      if (m === 'GET') return wiederherstellung.holen();
      if (m === 'PUT') return wiederherstellung.speichern(req);
    }
    if (p === '/v1/fotos/bekannt' && m === 'GET') return fotos.bekannt();
    const f = /^\/v1\/fotos\/([^/]+)\/([^/]+)$/.exec(p);
    // PUT: Heimherz-App; POST: so zeigt es Apples Beispiel für Upload-Jobs. Teil-Uploads (Resumable Upload) gibt es hier nicht.
    if (f && (m === 'PUT' || m === 'POST')) {
      if (req.headers.get('upload-complete') === '?0' || req.headers.get('upload-incomplete') === '?1') return leer(400);
      return fotos.empfange(req, f[1], f[2]);
    }
    if (p === '/v1/symbol' && m === 'GET') return symbole.antworte(url.searchParams.get('host'));
    if (p === '/v1/dateien' && m === 'GET') return dateien.liste(pfad);
    if (p === '/v1/dateien/suche' && m === 'GET') return dateien.suche(url.searchParams.get('q'), pfad);
    if (p === '/v1/dateien/vorschau' && m === 'GET') return dateien.vorschau(pfad, url.searchParams.get('px'));
    if (p === '/v1/datei') {
      if (m === 'GET') return dateien.herunterladen(pfad, req.headers.get('range'));
      if (m === 'PUT') return dateien.hochladen(req, pfad);
    }
    if (p === '/v1/datei/papierkorb' && m === 'POST') return dateien.inPapierkorb(req);
    // Dateien-Sync für die Dateien-App (SPEC 31): Kennungen statt Pfade
    if (p === '/v1/dateien/aenderungen' && m === 'GET') return sync.aenderungen(url.searchParams.get('anker'), url.searchParams.get('kurz') === '1');
    if (p === '/v1/dateien/kinder' && m === 'GET') return sync.kinder(url.searchParams.get('id'));
    if (p === '/v1/dateien/eintrag' && m === 'GET') return sync.eintrag(url.searchParams.get('id'));
    if (p === '/v1/dateien/neu' && m === 'PUT') return sync.neu(req, dateien, url.searchParams.get('eltern'), url.searchParams.get('name'));
    if (p === '/v1/dateien/ordner' && m === 'POST') return sync.ordner(req);
    if (p === '/v1/dateien/umbenennen' && m === 'POST') return sync.umbenennen(req);
    if (p === '/v1/dateien/ersetzen' && m === 'PUT') return sync.ersetzen(req, url.searchParams.get('id'), url.searchParams.get('fassung'));
    if (p === '/v1/dateien/papierkorb' && m === 'POST') return sync.papierkorb(req);
    return leer(404);
  }

  const server = Bun.serve({
    hostname: '127.0.0.1',
    port: o.port,
    development: false, // sonst zeigt Bun bei einer Ausnahme eine Fehlerseite mit Stacktrace und Pfaden
    error(e) { console.error('Fehler:', e?.message); return leer(500); },
    maxRequestBodySize: Number.MAX_SAFE_INTEGER, // Videos: Grenzen setzen wir selbst (Tresor 20 MB), alles andere läuft gestreamt
    idleTimeout: 120,
    async fetch(req, srv) {
      if (!istLoopback(srv.requestIP(req)?.address)) return leer(403);
      // Apples Vorabfrage der System-Uploads (Foto-Erweiterung): ohne Token, nur diese eine Auskunft. 501 = kein Resumable Upload.
      if (req.method === 'OPTIONS' && FOTO_OPTIONS.test(new URL(req.url).pathname)) return leer(501);
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
