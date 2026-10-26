// Symbole für Webseiten (SPEC 6): der PC holt das Bild direkt von der Seite selbst (kein Drittdienst) und gibt es dem Handy.
// Schutz vor Missbrauch (SSRF): nur gültige öffentliche Hostnamen, jede aufgelöste Adresse muss öffentlich sein, die Verbindung geht
// genau an die geprüfte Adresse (kein zweites Auflösen), nur https, Weiterleitungen werden jedes Mal neu geprüft.
import { lookup } from 'node:dns/promises';
import { request } from 'node:https';
import { chmodSync, mkdirSync, readFileSync } from 'node:fs';
import { isIP } from 'node:net';
import { join } from 'node:path';
import { leer } from './http';
import { schreibeAtomar } from './geraete';

export const MAX_BYTES = 256 * 1024;
export const FRIST_ANFRAGE_MS = 5000;
export const FRIST_GESAMT_MS = 10000;
const MAX_SPRUENGE = 3;
const PARALLEL = 4;
const TAGE_MS = 864e5;

// ---------- Adressen ----------

// IPv4 oder IPv6 als 4 bzw. 16 Bytes; null bei allem anderen (auch Zonen wie fe80::1%eth0).
export function ipBytes(ip: string): number[] | null {
  const art = isIP(ip);
  if (art === 4) return ip.split('.').map(Number);
  if (art !== 6) return null;
  let rest = ip.toLowerCase();
  let v4: number[] = [];
  const punkt = rest.lastIndexOf('.');
  if (punkt >= 0) {
    const teil = rest.slice(rest.lastIndexOf(':') + 1);
    const b = ipBytes(teil);
    if (!b || b.length !== 4) return null;
    v4 = b;
    rest = rest.slice(0, rest.lastIndexOf(':') + 1) + '0:0';
  }
  const [kopf, ende, zuviel] = rest.split('::');
  if (zuviel !== undefined) return null;
  const gruppen = (s: string) => (s === '' ? [] : s.split(':'));
  const k = gruppen(kopf), e = ende === undefined ? [] : gruppen(ende);
  const luecke = 8 - k.length - e.length;
  if (ende === undefined ? k.length !== 8 : luecke < 1) return null;
  const alle = [...k, ...Array(ende === undefined ? 0 : luecke).fill('0'), ...e].map(g => parseInt(g, 16));
  if (alle.length !== 8 || alle.some(n => !(n >= 0 && n <= 0xffff))) return null;
  const bytes = alle.flatMap(n => [n >> 8, n & 255]);
  if (v4.length) bytes.splice(12, 4, ...v4);
  return bytes;
}

function v4Oeffentlich([a, b, c]: number[]): boolean {
  if (a === 0 || a === 10 || a === 127) return false;
  if (a === 100 && b >= 64 && b <= 127) return false;     // CGNAT, Tailnet
  if (a === 169 && b === 254) return false;               // Link-lokal, Lumen-Metadaten
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  if (a === 198 && b === 51 && c === 100) return false;
  if (a === 203 && b === 0 && c === 113) return false;
  if (a >= 224) return false;                             // Multicast, reserviert, Broadcast
  return true;
}

export function istOeffentlich(ip: string): boolean {
  const b = ipBytes(ip);
  if (!b) return false;
  if (b.length === 4) return v4Oeffentlich(b);
  const null10 = b.slice(0, 10).every(x => x === 0);
  if (null10 && b[10] === 0xff && b[11] === 0xff) return v4Oeffentlich(b.slice(12));     // ::ffff:a.b.c.d
  if (b.slice(0, 12).every(x => x === 0)) return false;                                  // ::, ::1, ::a.b.c.d
  if (b[0] === 0 && b[1] === 0x64 && b[2] === 0xff && b[3] === 0x9b && b.slice(4, 12).every(x => x === 0)) return v4Oeffentlich(b.slice(12)); // 64:ff9b::/96
  if ((b[0] & 0xfe) === 0xfc) return false;                                              // fc00::/7
  if (b[0] === 0xfe && (b[1] & 0xc0) >= 0x80) return false;                              // fe80::/10 und fec0::/10
  if (b[0] === 0xff) return false;                                                       // Multicast
  if (b[0] === 0x20 && b[1] === 0x01 && b[2] === 0x0d && b[3] === 0xb8) return false;    // Dokumentation
  if (b[0] === 0x01 && b[1] === 0 && b.slice(2, 8).every(x => x === 0)) return false;    // 100::/64
  return true;
}

// ---------- Hostnamen ----------

const VERBOTENE_ENDUNGEN = ['local', 'localhost', 'internal', 'lan', 'home', 'corp', 'intranet', 'localdomain', 'ts.net', 'home.arpa', 'arpa', 'onion', 'invalid'];
const HOST = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+(xn--[a-z0-9-]{1,59}|[a-z]{2,63})$/;

// Gültiger öffentlicher Name in Kleinschreibung, sonst null. Keine IP-Adressen, keine Ports, keine Zugangsdaten, kein Pfad.
export function gueltigerHost(roh: string | null | undefined): string | null {
  if (!roh) return null;
  const h = roh.trim().toLowerCase();
  if (!HOST.test(h)) return null;
  if (VERBOTENE_ENDUNGEN.some(e => h === e || h.endsWith('.' + e))) return null;
  try { if (new URL('https://' + h).hostname !== h) return null; } catch { return null; }
  return h;
}

// ---------- Bildtypen ----------

// Nach den ersten Bytes, nie nach dem Content-Type (der Server der Seite könnte lügen). SVG fehlt mit Absicht (iOS kann es nicht laden).
export function bildTyp(b: Uint8Array): string | null {
  const ist = (...x: number[]) => x.every((v, i) => b[i] === v);
  if (b.length < 12) return null;
  if (ist(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) return 'image/png';
  if (ist(0xff, 0xd8, 0xff)) return 'image/jpeg';
  if (ist(0x47, 0x49, 0x46, 0x38)) return 'image/gif';
  if (ist(0x52, 0x49, 0x46, 0x46) && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return 'image/webp';
  if (ist(0, 0, 1, 0) && b[4] > 0) return 'image/x-icon';
  return null;
}

// Aus dem HTML die Symbol-Adressen, Apple-Symbole zuerst, dann größere vor kleineren. Nur die Adressen, geprüft wird später.
export function symbolLinks(html: string, basis: URL): URL[] {
  const treffer: { url: URL; rang: number }[] = [];
  for (const m of html.matchAll(/<link\b[^>]*>/gi)) {
    const tag = m[0];
    const attr = (n: string) => new RegExp(`\\b${n}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i').exec(tag);
    const w = (a: RegExpExecArray | null) => (a ? (a[2] ?? a[3] ?? a[4] ?? '') : '');
    const rel = w(attr('rel')).toLowerCase().split(/\s+/);
    const href = w(attr('href')).trim();
    if (!href || !(rel.includes('icon') || rel.includes('apple-touch-icon') || rel.includes('apple-touch-icon-precomposed'))) continue;
    let url: URL;
    try { url = new URL(href.replace(/&amp;/g, '&'), basis); } catch { continue; }
    const groesse = Number(/(\d+)x\d+/.exec(w(attr('sizes')))?.[1] ?? 0);
    treffer.push({ url, rang: (rel.some(r => r.startsWith('apple-touch-icon')) ? 10000 : 0) + Math.min(groesse, 512) });
  }
  return treffer.sort((a, b) => b.rang - a.rang).map(t => t.url);
}

// ---------- Netz (austauschbar für Tests) ----------

export type Antwort = { status: number; kopf: Record<string, string>; body: Uint8Array };
export type Adresse = { address: string; family: 4 | 6 };
export type Aufloeser = (host: string) => Promise<string[]>;
// Verbindet nur mit `ip` (Namen werden nie ein zweites Mal aufgelöst). Liefert höchstens MAX_BYTES Body; wirft bei Zeitablauf und Fehlern.
export type Holer = (url: URL, ip: Adresse, frist: number) => Promise<Antwort>;

export const echterAufloeser: Aufloeser = async host => (await lookup(host, { all: true })).map(a => a.address);

export const echterHoler: Holer = (url, ip, frist) => new Promise((ok, fehler) => {
  const r = request({
    protocol: 'https:', host: url.hostname, port: url.port || 443, path: url.pathname + url.search, method: 'GET', timeout: frist,
    headers: { 'user-agent': 'Heimherz-Symbol/1', accept: 'image/*,text/html;q=0.5' },
    // Genau die geprüfte Adresse; SNI und Zertifikat prüfen weiter gegen den Namen.
    lookup: (_h: string, o: any, cb: any) => (o?.all ? cb(null, [{ address: ip.address, family: ip.family }]) : cb(null, ip.address, ip.family)),
  }, res => {
    const teile: Buffer[] = [];
    let n = 0;
    res.on('data', (d: Buffer) => {
      n += d.length;
      if (n > MAX_BYTES) { teile.length = 0; r.destroy(new Error('zu gross')); return; }
      teile.push(d);
    });
    res.on('end', () => { clearTimeout(hart); ok({ status: res.statusCode ?? 0, kopf: Object.fromEntries(Object.entries(res.headers).map(([k, v]) => [k, String(v)])), body: Buffer.concat(teile) }); });
    res.on('error', e => { clearTimeout(hart); fehler(e); });
  });
  // `timeout` greift nur bei Stille am Socket; ein Server, der tröpfelt, wird hier nach `frist` hart abgebrochen.
  const hart = setTimeout(() => r.destroy(new Error('Zeit')), frist);
  r.on('timeout', () => r.destroy(new Error('Zeit')));
  r.on('error', e => { clearTimeout(hart); fehler(e); });
  r.end();
});

// ---------- Cache ----------

type CacheMeta = { host: string; typ: string | null; bis: number };

export type Treffer = { typ: string; bytes: Uint8Array } | 'keins';

class Cache {
  constructor(private ordner: string, private jetzt: () => number) {
    mkdirSync(ordner, { recursive: true, mode: 0o700 });
    chmodSync(ordner, 0o700);
  }
  private stamm = (host: string) => join(this.ordner, new Bun.CryptoHasher('sha256').update(host).digest('hex'));

  lies(host: string): Treffer | undefined {
    try {
      const meta: CacheMeta = JSON.parse(readFileSync(this.stamm(host) + '.json', 'utf8'));
      if (meta.host !== host || !(meta.bis > this.jetzt())) return undefined;
      if (meta.typ === null) return 'keins';
      return { typ: meta.typ, bytes: new Uint8Array(readFileSync(this.stamm(host) + '.bin')) };
    } catch { return undefined; }
  }

  schreibe(host: string, treffer: Treffer, bis: number) {
    // Erst das Bild, dann die Meta: eine halbe Ablage gilt nie als Treffer.
    if (treffer !== 'keins') schreibeAtomar(this.stamm(host) + '.bin', treffer.bytes);
    schreibeAtomar(this.stamm(host) + '.json', JSON.stringify({ host, typ: treffer === 'keins' ? null : treffer.typ, bis } satisfies CacheMeta));
  }
}

// ---------- Holen ----------

export type SymbolOptionen = { aufloeser?: Aufloeser; holer?: Holer; jetzt?: () => number };

export class Symbole {
  private cache: Cache;
  private aufloeser: Aufloeser;
  private holer: Holer;
  private jetzt: () => number;
  private laufend = new Map<string, Promise<Treffer>>();
  private frei = PARALLEL;
  private warte: (() => void)[] = [];

  constructor(daten: string, o: SymbolOptionen = {}) {
    this.jetzt = o.jetzt ?? Date.now;
    this.aufloeser = o.aufloeser ?? echterAufloeser;
    this.holer = o.holer ?? echterHoler;
    this.cache = new Cache(join(daten, 'symbole'), this.jetzt);
  }

  async antworte(hostRoh: string | null): Promise<Response> {
    const host = gueltigerHost(hostRoh);
    if (!host) return leer(400);
    const t = await this.hole(host);
    if (t === 'keins') return leer(404);
    return new Response(t.bytes, { headers: { 'content-type': t.typ, 'cache-control': 'private, max-age=86400', 'x-content-type-options': 'nosniff' } });
  }

  hole(host: string): Promise<Treffer> {
    const gemerkt = this.cache.lies(host);
    if (gemerkt) return Promise.resolve(gemerkt);
    const l = this.laufend.get(host) ?? this.suche(host).finally(() => this.laufend.delete(host));
    this.laufend.set(host, l);
    return l;
  }

  private async platz<T>(f: () => Promise<T>): Promise<T> {
    if (this.frei === 0) await new Promise<void>(w => this.warte.push(w));
    else this.frei--;
    try { return await f(); } finally {
      const n = this.warte.shift();
      if (n) n(); else this.frei++;
    }
  }

  private async suche(host: string): Promise<Treffer> {
    return this.platz(async () => {
      const ende = this.jetzt() + FRIST_GESAMT_MS;
      const stand = { fehler: false };
      const bild = await this.sucheBild(host, ende, stand);
      // Lag es an Netz oder Zeit (nicht an der Seite), nur kurz merken, sonst 30 Tage.
      const bis = this.jetzt() + (bild || !stand.fehler ? 30 * TAGE_MS : 3600_000);
      const t: Treffer = bild ?? 'keins';
      this.cache.schreibe(host, t, bis);
      return t;
    });
  }

  private async sucheBild(host: string, ende: number, stand: { fehler: boolean }): Promise<{ typ: string; bytes: Uint8Array } | null> {
    const basis = new URL(`https://${host}/`);
    const versuche: (() => Promise<URL[]>)[] = [
      async () => [new URL('/apple-touch-icon.png', basis)],
      async () => {
        const a = await this.folge(basis, ende, stand);
        if (!a || a.status !== 200 || !/html/i.test(a.kopf['content-type'] ?? '')) return [];
        return symbolLinks(new TextDecoder().decode(a.body), new URL(a.endUrl)).slice(0, 3);
      },
      async () => [new URL('/favicon.ico', basis)],
    ];
    for (const quelle of versuche) {
      for (const url of await quelle()) {
        const a = await this.folge(url, ende, stand);
        if (!a || a.status !== 200) continue;
        const typ = bildTyp(a.body);
        if (typ) return { typ, bytes: a.body };
      }
    }
    return null;
  }

  // Eine Adresse holen und Weiterleitungen folgen; jeder Sprung wird wie die erste Anfrage geprüft. null bei jedem Problem.
  private async folge(start: URL, ende: number, stand: { fehler: boolean }): Promise<(Antwort & { endUrl: string }) | null> {
    let url = start;
    for (let sprung = 0; sprung <= MAX_SPRUENGE; sprung++) {
      const frist = Math.min(FRIST_ANFRAGE_MS, ende - this.jetzt());
      if (frist <= 0) { stand.fehler = true; return null; }
      if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443')) return null;
      const host = gueltigerHost(url.hostname);
      if (!host) return null;
      let ip: Adresse;
      try {
        const adressen = await this.aufloeser(host);
        if (!adressen.length || !adressen.every(istOeffentlich)) return null;
        ip = { address: adressen[0], family: isIP(adressen[0]) === 6 ? 6 : 4 };
      } catch { stand.fehler = true; return null; }
      let a: Antwort;
      try { a = await this.holer(url, ip, frist); } catch { stand.fehler = true; return null; }
      if (a.status >= 300 && a.status < 400 && a.kopf.location) {
        try { url = new URL(a.kopf.location, url); } catch { return null; }
        continue;
      }
      return { ...a, endUrl: url.href };
    }
    return null;
  }
}
