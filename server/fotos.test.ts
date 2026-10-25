import { afterAll, expect, test } from 'bun:test';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bereinigeName, zeitName } from './fotos';
import { ablegeFehler, MINDEST_FREI } from './dateiio';
import { baue } from './testhilfe';
import { TEMPO_MAX_ZEILEN, TempoLog } from './tempo';

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

test('ohne Content-Length (Chunked, vollständig) wird angenommen', async () => {
  const strom = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(4)); c.close(); } });
  const r = await t.f('/v1/fotos/K1/foto', { method: 'PUT', body: strom as any, duplex: 'half' } as any);
  expect(r.status).toBe(200);
  expect((await bekannt()).some(x => x.kennung === 'K1' && x.groesse === 4)).toBe(true);
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

test('Chunked-Upload ohne Endblock hinterlässt nichts, mit Endblock wird er gespeichert', async () => {
  const vorher = alleDateien(t.fotos);
  const n = (await bekannt()).length;
  let zu!: () => void;
  const fertig = new Promise<void>(r => (zu = r));
  const s = await Bun.connect({ hostname: '127.0.0.1', port: t.server.port!, socket: { data() {}, close() { zu(); }, open(sock) {
    sock.write(`PUT /v1/fotos/CHUNK/foto HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${t.token}\r\nTransfer-Encoding: chunked\r\n\r\n`);
    sock.write(`1388\r\n`); sock.write(new Uint8Array(0x1388)); sock.write('\r\n'); // ein Chunk, dann ohne "0\r\n\r\n" weg
    setTimeout(() => sock.end(), 100);
  } } });
  await fertig;
  await Bun.sleep(300);
  s.end();
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect((await bekannt()).length).toBe(n);
  // der vollständige rohe Chunked-Upload mit Endblock wird gespeichert
  let ok!: () => void;
  const antwort = new Promise<string>(r => (ok = () => r('')));
  let text = '';
  const s2 = await Bun.connect({ hostname: '127.0.0.1', port: t.server.port!, socket: { data(_, d) { text += d.toString(); if (text.includes('\r\n\r\n')) ok(); }, open(sock) {
    sock.write(`PUT /v1/fotos/CHUNK2/foto HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer ${t.token}\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhallo\r\n0\r\n\r\n`);
  } } });
  await antwort;
  s2.end();
  expect(text.startsWith('HTTP/1.1 200')).toBe(true);
  expect((await bekannt()).some(x => x.kennung === 'CHUNK2' && x.groesse === 5)).toBe(true);
  expect((await bekannt()).some(x => x.kennung === 'CHUNK')).toBe(false);
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

test('POST (so legt Apples Upload-Job an) speichert wie PUT; ohne Token 401; doppelt = 200 ohne Schreiben', async () => {
  const h = { 'x-aufnahme': '2026-10-26T08:00:00', 'x-dateiname': 'IMG_0100.MOV', 'upload-incomplete': '?0', 'content-type': 'application/octet-stream' };
  const post = (k: string, r: string, body: BodyInit | null, kopf: Record<string, string> = h) =>
    t.f(`/v1/fotos/${k}/${r}`, { method: 'POST', headers: kopf, body });
  expect((await t.ohne('/v1/fotos/POST1/video-0', { method: 'POST', body: new Uint8Array(3) })).status).toBe(401);
  expect((await post('POST1', 'video-0', new Uint8Array([5, 6, 7]))).status).toBe(200);
  expect([...readFileSync(join(t.fotos, '2026/10/2026-10-26_08-00-00_IMG_0100.MOV'))]).toEqual([5, 6, 7]);
  const vorher = alleDateien(t.fotos);
  expect((await post('POST1', 'video-0', new Uint8Array([9, 9, 9]))).status).toBe(200);
  expect(alleDateien(t.fotos)).toEqual(vorher);
  expect((await bekannt()).filter(x => x.kennung === 'POST1')).toEqual([{ kennung: 'POST1', ressource: 'video-0', groesse: 3 }]);
});

test('POST: Ausbruch-Kennungen abgelehnt, Teil-Upload (Resumable) abgelehnt', async () => {
  const vorher = alleDateien(t.fotos);
  for (const [k, r] of [['a.b', 'x'], ['k', 'a b'], ['x'.repeat(129), 'r'], ['k%2Fx', 'r']])
    expect((await t.f(`/v1/fotos/${k}/${r}`, { method: 'POST', body: new Uint8Array(1) })).status).toBe(400);
  for (const kopf of [{ 'upload-complete': '?0' }, { 'upload-incomplete': '?1' }])
    expect((await t.f('/v1/fotos/TEIL/foto-0', { method: 'POST', headers: kopf, body: new Uint8Array(1) })).status).toBe(400);
  expect((await t.f('/v1/fotos/TEIL/foto-0', { method: 'POST', headers: { 'upload-complete': '?1' }, body: new Uint8Array(1) })).status).toBe(200);
  expect(alleDateien(t.fotos).length).toBe(vorher.length + 1);
});

test('Dateiname: höchstens 200 UTF-8-Bytes, geschnitten an einer Zeichengrenze, Endung bleibt', async () => {
  const bytes = (x: string) => Buffer.byteLength(x);
  for (const stamm of ['ä', '日', '😀', 'a']) {
    const n = bereinigeName(stamm.repeat(300) + '.jpg');
    expect(bytes(n)).toBeLessThanOrEqual(200);
    expect(bytes(n)).toBeGreaterThan(200 - bytes(stamm));
    expect(n.endsWith('.jpg')).toBe(true);
    expect(n).not.toContain('\uFFFD');
    expect(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.from(n))).toBe(n);
  }
  expect(bytes(bereinigeName('😀'.repeat(300)))).toBe(200);
  expect(bereinigeName('ä'.repeat(100))).toBe('ä'.repeat(100)); // genau 200 Bytes bleiben ganz
  // bis zur Platte: ein Name aus 300 Emoji (1200 Bytes) wird gespeichert statt 500
  const r = await foto('LANG', 'foto', new Uint8Array(2), { 'x-aufnahme': '2026-05-06T07:08:09', 'x-dateiname': encodeURIComponent('😀'.repeat(300) + '.heic') });
  expect(r.status).toBe(200);
  expect(alleDateien(t.fotos).filter(x => x.startsWith('2026/05/')).every(x => bytes(x.split('/').pop()!) <= 255)).toBe(true);
});

test('Fehler beim Ablegen: Platte voll 507, unmöglicher Name 400, anderes bleibt unbekannt (null)', () => {
  expect(ablegeFehler(Object.assign(new Error('x'), { code: 'ENOSPC' }))?.status).toBe(507);
  expect(ablegeFehler(Object.assign(new Error('x'), { code: 'EDQUOT' }))?.status).toBe(507);
  expect(ablegeFehler(Object.assign(new Error('x'), { code: 'ENAMETOOLONG' }))?.status).toBe(400);
  expect(ablegeFehler(Object.assign(new Error('x'), { code: 'EACCES' }))).toBeNull();
  expect(ablegeFehler(new Error('x'))).toBeNull();
});

test('wenig freier Platz: Foto-Upload ist 507, nichts liegt da; Standard sind 5 GB', async () => {
  expect(MINDEST_FREI).toBe(5 * 1024 ** 3);
  const voll = baue({ mindestFrei: Number.MAX_SAFE_INTEGER });
  try {
    const r = await voll.f('/v1/fotos/VOLL/foto', { method: 'PUT', body: new Uint8Array(3) });
    expect(r.status).toBe(507);
    expect(alleDateien(voll.fotos)).toEqual([]);
    expect((await voll.f('/v1/status')).status).toBe(200);
    expect(await (await voll.f('/v1/fotos/bekannt')).json()).toEqual([]);
  } finally { voll.ende(); }
});

test('neue Foto-Dateien 0600, neue Ordner 0700', async () => {
  const r = await foto('MODUS', 'foto', new Uint8Array(2), { 'x-aufnahme': '2031-02-03T04:05:06', 'x-dateiname': 'm.jpg' });
  expect(r.status).toBe(200);
  const modus = (p: string) => statSync(p).mode & 0o777;
  expect(modus(join(t.fotos, '2031/02/2031-02-03_04-05-06_m.jpg'))).toBe(0o600);
  for (const d of [t.fotos, join(t.fotos, '2031'), join(t.fotos, '2031/02'), join(t.fotos, '.teil')]) expect([d, modus(d)]).toEqual([d, 0o700]);
});

test('Tempo: je Upload eine Zeile mit nur Zahlen, Datei 0600, ungültige Kopfzeilen werden null', async () => {
  const datei = join(t.daten, 'foto-tempo.jsonl');
  const h = { 'x-heim-export-ms': '120', 'x-heim-warte-ms': '35', 'x-heim-aktiv': '6', 'x-heim-exporte': '3', 'x-heim-vordergrund': '1', 'x-heim-durchgang': 'lokal', 'x-heim-session': 'vorder', 'x-heim-aufgeschoben': '412', 'x-heim-haenger': '2' };
  expect((await foto('T1', 'foto-0', new Uint8Array(10), { ...h, 'x-dateiname': 'GEHEIM.HEIC' })).status).toBe(200);
  expect((await foto('T2', 'alternative-0', new Uint8Array(7), { 'x-heim-export-ms': 'abc', 'x-heim-durchgang': 'quatsch', 'x-heim-vordergrund': '2' })).status).toBe(200);
  const zeilen = readFileSync(datei, 'utf8').trim().split('\n').map(z => JSON.parse(z));
  const a = zeilen.find(z => z.bytes === 10 && z.exportMs === 120)!, b = zeilen.find(z => z.bytes === 7 && z.art === 'alternative')!;
  expect(a).toMatchObject({ bytes: 10, ergebnis: 'neu', exportMs: 120, warteMs: 35, aktiv: 6, exporte: 3, vordergrund: 1, durchgang: 'lokal', session: 'vorder', aufgeschoben: 412, haenger: 2 });
  expect(a.empfangMs).toBeGreaterThanOrEqual(0);
  expect(a.gesamtMs).toBeGreaterThanOrEqual(a.empfangMs);
  expect(new Date(a.zeit).getTime()).toBeGreaterThan(0);
  expect(b).toMatchObject({ bytes: 7, exportMs: null, warteMs: null, vordergrund: null, durchgang: null, session: null, aufgeschoben: null, haenger: null });
  expect(readFileSync(datei, 'utf8')).not.toContain('GEHEIM');
  expect(statSync(datei).mode & 0o777).toBe(0o600);
});

test('Tempo: Doppeltes wird als schon (0 Bytes) gezählt', async () => {
  await foto('T1', 'foto-0', new Uint8Array(10));
  const z = readFileSync(join(t.daten, 'foto-tempo.jsonl'), 'utf8').trim().split('\n').map(x => JSON.parse(x));
  expect(z.some(x => x.ergebnis === 'schon' && x.bytes === 0)).toBe(true);
});

test('Tempo: nach 20.000 Zeilen wird rotiert (.1), neue Datei beginnt leer', () => {
  const ordner = mkdtempSync(join(tmpdir(), 'tempo-'));
  const log = new TempoLog(ordner, 3);
  const z = { zeit: 'x', bytes: 1, empfangMs: 1, gesamtMs: 1, ergebnis: 'neu', art: 'foto', exportMs: null, warteMs: null, aktiv: null, exporte: null, vordergrund: null, durchgang: null, session: null } as const;
  for (let i = 0; i < 4; i++) log.schreibe(z);
  expect(readFileSync(join(ordner, 'foto-tempo.jsonl'), 'utf8').trim().split('\n')).toHaveLength(1);
  expect(readFileSync(join(ordner, 'foto-tempo.jsonl.1'), 'utf8').trim().split('\n')).toHaveLength(3);
  expect(new TempoLog(ordner, 3)).toBeTruthy(); // zählt die vorhandene Zeile, wirft nicht
  expect(TEMPO_MAX_ZEILEN).toBe(20_000);
  rmSync(ordner, { recursive: true, force: true });
});
