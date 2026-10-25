import { afterAll, expect, test } from 'bun:test';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import fx from '../fixtures/tresor/umschlag-1.json';
import { baue, testUmschlag } from './testhilfe';

const t = baue({ verlaufMax: 3 });
afterAll(t.ende);

const put = (u: unknown, rev: string | null, roh?: BodyInit) =>
  t.f('/v1/tresor', { method: 'PUT', headers: rev === null ? {} : { 'if-match': rev }, body: roh ?? JSON.stringify(u) });

test('leer: GET 404, Status rev 0', async () => {
  expect((await t.f('/v1/tresor')).status).toBe(404);
  const s = await (await t.f('/v1/status')).json() as any;
  expect(s).toMatchObject({ version: expect.any(String), rev: 0, fotos: 0 });
  expect(s.frei).toBeGreaterThan(0);
  expect(s.belegt).toBeGreaterThan(0);
});

test('erster PUT mit If-Match 0 vergibt rev 1 und ignoriert die rev aus dem Body', async () => {
  const r = await put(await testUmschlag('a', 99), '0');
  expect(r.status).toBe(200);
  expect((await r.json() as any).rev).toBe(1);
  const g = await (await t.f('/v1/tresor')).json() as any;
  expect(g.rev).toBe(1);
  expect(Object.keys(g).sort()).toEqual(['daten', 'nonce', 'rev', 'v']);
  expect(existsSync(join(t.daten, 'tresor/aktuell.json'))).toBe(true);
});

test('falsche oder fehlende rev: 409 mit aktuellem Umschlag, fehlender Header 428', async () => {
  const u = await testUmschlag('b');
  const r = await put(u, '0');
  expect(r.status).toBe(409);
  expect((await r.json() as any).rev).toBe(1);
  expect((await put(u, '5')).status).toBe(409);
  expect((await put(u, null)).status).toBe(428);
  expect((await put(u, 'abc')).status).toBe(428);
  expect((await t.f('/v1/status').then(r => r.json()) as any).rev).toBe(1);
});

test('If-Match darf in Anführungszeichen stehen (ETag-Stil)', async () => {
  expect((await put(await testUmschlag('c'), '"1"')).status).toBe(200);
});

test('Form wird geprüft, Müll ist 400, nichts ändert sich', async () => {
  const rev = (await t.f('/v1/status').then(r => r.json()) as any).rev;
  for (const roh of ['kein json', '{}', JSON.stringify({ ...fx.umschlag, v: 2 }), JSON.stringify({ ...fx.umschlag, nonce: 'AAAA' })])
    expect((await put(null, String(rev), roh)).status).toBe(400);
  expect((await t.f('/v1/status').then(r => r.json()) as any).rev).toBe(rev);
});

test('Größe: über 20 MB ist 413', async () => {
  const rev = (await t.f('/v1/status').then(r => r.json()) as any).rev;
  const gross = new Uint8Array(20 * 1024 * 1024 + 1).fill(97);
  expect((await put(null, String(rev), gross)).status).toBe(413);
  // ohne Content-Length (Chunked) greift die Grenze ebenfalls
  const strom = new ReadableStream({ start(c) { c.enqueue(gross); c.close(); } });
  expect((await t.f('/v1/tresor', { method: 'PUT', headers: { 'if-match': String(rev) }, body: strom as any, duplex: 'half' } as any)).status).toBe(413);
});

test('Verlauf: alte Fassungen liegen unter verlauf/<rev>.json, nur die letzten N bleiben', async () => {
  for (let i = 0; i < 6; i++) {
    const rev = (await t.f('/v1/status').then(r => r.json()) as any).rev;
    expect((await put(await testUmschlag('v' + i), String(rev))).status).toBe(200);
  }
  const rev = (await t.f('/v1/status').then(r => r.json()) as any).rev;
  expect(rev).toBe(8);
  const dateien = readdirSync(join(t.daten, 'tresor/verlauf')).sort();
  expect(dateien).toEqual(['5.json', '6.json', '7.json']);
  expect(JSON.parse(readFileSync(join(t.daten, 'tresor/verlauf/7.json'), 'utf8')).rev).toBe(7);
});

test('gleichzeitige PUTs mit derselben rev: genau einer gewinnt', async () => {
  const rev = String((await t.f('/v1/status').then(r => r.json()) as any).rev);
  const rs = await Promise.all([1, 2, 3, 4].map(async i => put(await testUmschlag('p' + i), rev)));
  expect(rs.map(r => r.status).sort()).toEqual([200, 409, 409, 409]);
});

test('Umschlag bleibt über den Server hinweg entschlüsselbar', async () => {
  const { oeffne, schluessel, b64 } = await import('../lib/umschlag');
  const k = await schluessel(b64(fx.schluessel));
  const g = await (await t.f('/v1/tresor')).json() as any;
  expect((await oeffne(g, k) as any).format).toBe(1);
});

test('aktuell.json kaputt oder keine Hülle: 500 auf allen Wegen, nichts wird überschrieben, rev fällt nie auf 0', async () => {
  const d = baue();
  try {
    expect((await d.f('/v1/tresor', { method: 'PUT', headers: { 'if-match': '0' }, body: JSON.stringify(await testUmschlag('a')) })).status).toBe(200);
    const pfad = join(d.daten, 'tresor/aktuell.json');
    for (const kaputt of ['{"v":1,"rev":1,"nonce":"abc', 'null', '{"v":1,"rev":1}', '']) {
      writeFileSync(pfad, kaputt);
      for (const [methode, route, kopf] of [['GET', '/v1/tresor', {}], ['GET', '/v1/status', {}], ['PUT', '/v1/tresor', { 'if-match': '0' }], ['PUT', '/v1/tresor', { 'if-match': '1' }]] as const) {
        const r = await d.f(route, { method: methode, headers: kopf, body: methode === 'PUT' ? JSON.stringify(await testUmschlag('b')) : undefined });
        expect([kaputt, methode, route, r.status, await r.text()]).toEqual([kaputt, methode, route, 500, '']);
      }
      expect(readFileSync(pfad, 'utf8')).toBe(kaputt);
      expect(readdirSync(join(d.daten, 'tresor/verlauf'))).toEqual([]);
    }
  } finally { d.ende(); }
});
