import { afterAll, expect, test } from 'bun:test';
import fx from '../fixtures/sicherung/wiederherstellung-1.json';
import { baue } from './testhilfe';

const t = baue();
afterAll(t.ende);
const put = (body: BodyInit) => t.f('/v1/wiederherstellung', { method: 'PUT', body });

test('ohne Token 401, leer 404', async () => {
  expect((await t.ohne('/v1/wiederherstellung')).status).toBe(401);
  expect((await t.f('/v1/wiederherstellung')).status).toBe(404);
});

test('PUT speichert nur Blattfelder, GET liefert sie, neuer PUT ersetzt', async () => {
  const r = await put(JSON.stringify({ ...fx.blatt, extra: 'x' }));
  expect(r.status).toBe(200);
  expect(await (await t.f('/v1/wiederherstellung')).json()).toEqual(fx.blatt);
  const neu = { ...fx.blatt, nonce: 'AAAAAAAAAAAAAAAA' };
  expect((await put(JSON.stringify(neu))).status).toBe(200);
  expect(await (await t.f('/v1/wiederherstellung')).json()).toEqual(neu);
});

test('Müll und zu große Anfrage werden abgelehnt, altes Blatt bleibt', async () => {
  expect((await put('kein json')).status).toBe(400);
  expect((await put(JSON.stringify({ ...fx.blatt, daten: 'abc' }))).status).toBe(400);
  expect((await put('x'.repeat(5000))).status).toBe(413);
  expect(((await (await t.f('/v1/wiederherstellung')).json()) as any).nonce).toBe('AAAAAAAAAAAAAAAA');
});
