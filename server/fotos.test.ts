import { afterAll, expect, test } from 'bun:test';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { bereinigeName, zeitName } from './fotos';
import { baue } from './testhilfe';

const t = baue();
afterAll(t.ende);

const foto = (k: string, r: string, body: BodyInit | null, h: Record<string, string> = {}) =>
  t.f(`/v1/fotos/${k}/${r}`, { method: 'PUT', headers: h, body });
const bekannt = async () => (await (await t.f('/v1/fotos/bekannt')).json()) as any[];
const alleDateien = (dir: string): string[] => readdirSync(dir, { withFileTypes: true }).flatMap(e => e.isDirectory() ? alleDateien(join(dir, e.name)).map(x => join(e.name, x)) : [e.name]);

test('Upload landet unter JJJJ/MM/<Datum>_<Name> und ist bekannt', async () => {
  const r = await foto('K1', 'foto', new Uint8Array([1, 2, 3, 4]), { 'x-aufnahme': '2026-10-25T01:40:07', 'x-dateiname': 'IMG_0001.HEIC' });
  expect(r.status).toBe(200);
  const ziel = join(t.fotos, '2026/10/2026-10-25_01-40-07_IMG_0001.HEIC');
  expect([...readFileSync(ziel)]).toEqual([1, 2, 3, 4]);
  expect(await bekannt()).toEqual([{ kennung: 'K1', ressource: 'foto', groesse: 4 }]);
  expect((await (await t.f('/v1/status')).json() as any).fotos).toBe(1);
});

test('Datum steckt im Header; ohne gültiges Datum gilt jetzt', () => {
  expect(zeitName('2026-01-02T03:04:05').stempel).toBe('2026-01-02_03-04-05');
  const jetzt = new Date(2027, 5, 7, 8, 9, 10);
  expect(zeitName(null, jetzt)).toEqual({ jahr: '2027', monat: '06', stempel: '2027-06-07_08-09-10' });
  expect(zeitName('quatsch', jetzt).jahr).toBe('2027');
});

test('doppelt: gleiche Kennung und Größe = 200 ohne Schreiben', async () => {
  const vorher = alleDateien(t.fotos);
  const r = await foto('K1', 'foto', new Uint8Array([9, 9, 9, 9]), { 'x-aufnahme': '2026-10-25T01:40:07', 'x-dateiname': 'IMG_0001.HEIC' });
  expect(r.status).toBe(200);
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect([...readFileSync(join(t.fotos, '2026/10/2026-10-25_01-40-07_IMG_0001.HEIC'))]).toEqual([1, 2, 3, 4]);
  expect(await bekannt()).toHaveLength(1);
});

test('doppelt ohne Content-Length (Chunked) schreibt ebenfalls nichts', async () => {
  const strom = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(4)); c.close(); } });
  const vorher = alleDateien(t.fotos);
  const r = await t.f('/v1/fotos/K1/foto', { method: 'PUT', body: strom as any, duplex: 'half' } as any);
  expect(r.status).toBe(200);
  expect(alleDateien(t.fotos)).toEqual(vorher);
});

test('andere Ressource derselben Kennung (Live Photo) und Namensgleichheit bekommt (2)', async () => {
  const h = { 'x-aufnahme': '2026-10-25T01:40:07', 'x-dateiname': 'IMG_0001.HEIC' };
  expect((await foto('K1', 'video', new Uint8Array(5), h)).status).toBe(200);
  expect((await foto('K2', 'foto', new Uint8Array(6), h)).status).toBe(200);
  expect(alleDateien(t.fotos).filter(f => f.endsWith('.HEIC')).sort()).toEqual([
    '2026/10/2026-10-25_01-40-07_IMG_0001 (2).HEIC', '2026/10/2026-10-25_01-40-07_IMG_0001 (3).HEIC', '2026/10/2026-10-25_01-40-07_IMG_0001.HEIC']);
  expect(await bekannt()).toHaveLength(3);
});

test('Kennung und Ressource nur [A-Za-z0-9_-]{1,128}', async () => {
  const vorher = alleDateien(t.fotos);
  for (const [k, r] of [['a.b', 'x'], ['k', 'a b'], ['x'.repeat(129), 'r'], ['k', 'x'.repeat(129)], ['k%2Fx', 'r']])
    expect([k.slice(0, 8), r.slice(0, 8), (await foto(k, r, new Uint8Array(1))).status]).toEqual([k.slice(0, 8), r.slice(0, 8), 400]);
  expect((await t.f('/v1/fotos/a/b/c', { method: 'PUT', body: 'x' })).status).toBe(404);
  expect((await t.f('/v1/fotos/%2e%2e/x', { method: 'PUT', body: 'x' })).status).toBeGreaterThanOrEqual(400); // der URL-Parser macht daraus schon einen anderen Pfad
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect((await foto('x'.repeat(128), 'r', new Uint8Array(1))).status).toBe(200);
});

test('Dateiname wird bereinigt: keine Trenner, keine Steuerzeichen, höchstens 200 Zeichen', async () => {
  expect(bereinigeName('../../etc/passwd')).toBe('.._.._etc_passwd');
  expect(bereinigeName('a\\b\u0000c\nd.jpg')).toBe('a_b_c_d.jpg');
  expect(bereinigeName(null)).toBe('datei');
  expect(bereinigeName('..')).toBe('datei');
  const lang = bereinigeName('a'.repeat(300) + '.jpg');
  expect(lang.length).toBe(200);
  expect(lang.endsWith('.jpg')).toBe(true);
  expect(bereinigeName('Grüße%20aus.png')).toBe('Grüße aus.png');
  const r = await foto('K9', 'foto', new Uint8Array(1), { 'x-aufnahme': '2026-03-04T05:06:07', 'x-dateiname': '../../../boese.jpg' });
  expect(r.status).toBe(200);
  expect(existsSync(join(t.fotos, '2026/03/2026-03-04_05-06-07_.._.._.._boese.jpg'))).toBe(true);
  expect(existsSync(join(t.wurzel, 'boese.jpg'))).toBe(false);
});

test('abgebrochener Upload hinterlässt nichts Halbes und gilt nicht als bekannt', async () => {
  const vorher = alleDateien(t.fotos);
  const n = (await bekannt()).length;
  let zu!: () => void;
  const fertig = new Promise<void>(r => (zu = r));
  const s = await Bun.connect({ hostname: '127.0.0.1', port: t.server.port!, socket: { data() {}, close() { zu(); }, open(sock) {
    sock.write(`PUT /v1/fotos/ABBRUCH/foto HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${t.token}\r\nContent-Length: 100000\r\nX-Dateiname: halb.jpg\r\n\r\n`);
    sock.write(new Uint8Array(5000));
    setTimeout(() => sock.end(), 100);
  } } });
  await fertig;
  await Bun.sleep(300);
  s.end();
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect(readdirSync(join(t.fotos, '.teil'))).toEqual([]);
  expect(await bekannt()).toHaveLength(n);
  // Wiederholung klappt, die Kennung ist nicht blockiert
  expect((await foto('ABBRUCH', 'foto', new Uint8Array(3), { 'x-dateiname': 'ganz.jpg' })).status).toBe(200);
});

test('Content-Length passt nicht zum Body: abgelehnt, nichts liegt da', async () => {
  const strom = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(10)); c.close(); } });
  const vorher = alleDateien(t.fotos);
  const r = await t.f('/v1/fotos/LAENGE/foto', { method: 'PUT', headers: { 'content-length': '20' }, body: strom as any, duplex: 'half' } as any).catch(() => null);
  if (r) expect(r.status).toBeGreaterThanOrEqual(400);
  await Bun.sleep(300);
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect((await bekannt()).some(x => x.kennung === 'LAENGE')).toBe(false);
});

test('große Videos: über 128 MB (Bun-Standardgrenze) kommen vollständig an', async () => {
  const gross = new Uint8Array(140 * 1024 * 1024).fill(7);
  const r = await foto('GROSS', 'video', gross, { 'x-aufnahme': '2026-10-25T10:00:00', 'x-dateiname': 'film.mov' });
  expect(r.status).toBe(200);
  expect(statSync(join(t.fotos, '2026/10/2026-10-25_10-00-00_film.mov')).size).toBe(gross.length);
});
