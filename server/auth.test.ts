import { afterAll, expect, test } from 'bun:test';
import { chmodSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { hashe, leseGeraete, schreibeGeraete } from './geraete';
import { istLoopback } from './dienst';
import { baue } from './testhilfe';

const t = baue();
afterAll(t.ende);

const ROUTEN: [string, string][] = [
  ['GET', '/v1/status'], ['GET', '/v1/tresor'], ['PUT', '/v1/tresor'], ['GET', '/v1/fotos/bekannt'], ['PUT', '/v1/fotos/abc/def'],
  ['GET', '/v1/symbol?host=example.org'], ['GET', '/v1/dateien'], ['GET', '/v1/datei?pfad=a'], ['PUT', '/v1/datei?pfad=a'], ['POST', '/v1/datei/papierkorb'], ['GET', '/v1/gibtsnicht'],
];

test('jede Route ohne oder mit falschem Token: 401 ohne Text', async () => {
  for (const [m, p] of ROUTEN) {
    for (const h of [{}, { authorization: 'Bearer falsch' }, { authorization: 'Basic abc' }, { authorization: 'Bearer ' }]) {
      const r = await t.ohne(p, { method: m, headers: h, body: m === 'GET' ? undefined : 'x' });
      expect([m, p, r.status]).toEqual([m, p, 401]);
      expect(await r.text()).toBe('');
    }
  }
});

test('mit Token ist der Dienst erreichbar', async () => {
  expect((await t.f('/v1/status')).status).toBe(200);
});

test('zuletzt wird gesetzt, aber höchstens einmal pro Minute geschrieben', async () => {
  await t.f('/v1/status');
  const a = leseGeraete(t.daten)[0].zuletzt;
  expect(a).not.toBeNull();
  await t.f('/v1/status');
  expect(leseGeraete(t.daten)[0].zuletzt).toBe(a);
  expect(existsSync(join(t.daten, 'geraete.json'))).toBe(true);
  expect(readFileSync(join(t.daten, 'geraete.json'), 'utf8')).not.toContain(t.token); // nur der Hash
});

test('Geräte, die das CLI nachträglich einträgt, gelten sofort; ausgetragene nicht mehr', async () => {
  const neu = 'neues-token-123';
  const liste = leseGeraete(t.daten);
  schreibeGeraete(t.daten, [...liste, { id: 'g2', name: 'handy', hash: hashe(neu), angelegt: '2026-10-25T00:00:00.000Z', zuletzt: null }]);
  expect((await t.ohne('/v1/status', { headers: { authorization: `Bearer ${neu}` } })).status).toBe(200);
  schreibeGeraete(t.daten, liste);
  expect((await t.ohne('/v1/status', { headers: { authorization: `Bearer ${neu}` } })).status).toBe(401);
  expect((await t.f('/v1/status')).status).toBe(200);
});

test('nur Loopback', () => {
  expect(istLoopback('127.0.0.1')).toBe(true);
  expect(istLoopback('::1')).toBe(true);
  for (const x of ['100.64.0.5', '192.168.1.2', '0.0.0.0', '', undefined]) expect(istLoopback(x)).toBe(false);
});

// Apples Vorabfrage der System-Uploads (PHAssetResourceUploadJob): OPTIONS ohne Token, genau eine Auskunft, sonst nichts.
test('OPTIONS auf einen Foto-Upload-Pfad: 501 ohne Token, ohne Text; sonst bleibt alles 401', async () => {
  const r = await t.ohne('/v1/fotos/abc/foto-0', { method: 'OPTIONS' });
  expect([r.status, await r.text(), r.headers.get('upload-limit')]).toEqual([501, '', null]);
  for (const p of ['/v1/status', '/v1/tresor', '/v1/fotos/bekannt/x/y', '/v1/fotos/a.b/foto', '/v1/fotos/abc', '/v1/fotos/abc/def/ghi', '/v1/datei?pfad=a', '/v1/fotos/%2e%2e/x', `/v1/fotos/${'x'.repeat(129)}/r`]) {
    const o = await t.ohne(p, { method: 'OPTIONS' });
    expect([p, o.status, await o.text()]).toEqual([p, 401, '']);
  }
});

test('OPTIONS auf einen Foto-Pfad legt nichts an', async () => {
  const vorher = (await (await t.f('/v1/fotos/bekannt')).json()) as unknown[];
  await t.ohne('/v1/fotos/OPT/foto-0', { method: 'OPTIONS' });
  await t.f('/v1/fotos/OPT/foto-0', { method: 'OPTIONS' });
  expect(await (await t.f('/v1/fotos/bekannt')).json()).toEqual(vorher);
});

test('geworfene Ausnahme außerhalb der Routen: leer 500, kein Stacktrace, keine Pfade', async () => {
  const d = baue();
  try {
    // Die Anmeldung muss "zuletzt" schreiben; ist der Datenordner schreibgeschützt, wirft sie außerhalb des Routen-try.
    chmodSync(d.daten, 0o500);
    const r = await d.f('/v1/status');
    expect(r.status).toBe(500);
    expect(await r.text()).toBe('');
    expect(r.headers.get('content-type') ?? '').not.toContain('html');
  } finally { chmodSync(d.daten, 0o700); d.ende(); }
});
