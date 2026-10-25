import { afterAll, beforeAll, expect, test } from 'bun:test';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { baue } from './testhilfe';

const t = baue();
afterAll(t.ende);
const q = (s: string) => encodeURIComponent(s);
const aussen = () => join(t.wurzel, 'aussen');

beforeAll(() => {
  mkdirSync(aussen(), { recursive: true });
  writeFileSync(join(aussen(), 'geheim.txt'), 'GEHEIM');
  writeFileSync(join(t.dateien, 'a.txt'), '0123456789');
  mkdirSync(join(t.dateien, 'ordner'));
  writeFileSync(join(t.dateien, 'ordner/b.pdf'), 'pdf');
  symlinkSync(join(aussen(), 'geheim.txt'), join(t.dateien, 'link-datei'));
  symlinkSync(aussen(), join(t.dateien, 'link-ordner'));
  symlinkSync(join(aussen(), 'gibtsnicht.txt'), join(t.dateien, 'link-leer'));
  symlinkSync(join(t.dateien, 'a.txt'), join(t.dateien, 'link-innen'));
});

test('Liste: Ordner zuerst, Felder stimmen, Symlinks nach draußen unsichtbar', async () => {
  const r = await t.f('/v1/dateien');
  expect(r.status).toBe(200);
  const l = await r.json() as any[];
  expect(l.map(x => x.name)).toEqual(['ordner', 'a.txt', 'link-innen']);
  expect(l[0]).toMatchObject({ name: 'ordner', ordner: true });
  expect(l[1]).toMatchObject({ name: 'a.txt', ordner: false, groesse: 10 });
  expect(Date.parse(l[1].geaendert)).toBeGreaterThan(0);
  expect((await (await t.f(`/v1/dateien?pfad=${q('ordner')}`)).json() as any[]).map(x => x.name)).toEqual(['b.pdf']);
  expect((await t.f(`/v1/dateien?pfad=${q('gibtsnicht')}`)).status).toBe(404);
  expect((await t.f(`/v1/dateien?pfad=${q('a.txt')}`)).status).toBe(400);
});

test('Download ganz, mit Range, ohne Range-Syntax, außerhalb', async () => {
  const r = await t.f(`/v1/datei?pfad=${q('a.txt')}`);
  expect([r.status, await r.text(), r.headers.get('accept-ranges')]).toEqual([200, '0123456789', 'bytes']);
  const faelle: [string, number, string, string | null][] = [
    ['bytes=0-3', 206, '0123', 'bytes 0-3/10'],
    ['bytes=7-', 206, '789', 'bytes 7-9/10'],
    ['bytes=-3', 206, '789', 'bytes 7-9/10'],
    ['bytes=5-100', 206, '56789', 'bytes 5-9/10'],
    ['bytes=10-', 416, '', 'bytes */10'],
    ['bytes=5-2', 416, '', 'bytes */10'],
    ['bytes=-', 200, '0123456789', null],
    ['quatsch', 200, '0123456789', null],
  ];
  for (const [range, status, text, cr] of faelle) {
    const x = await t.f(`/v1/datei?pfad=${q('a.txt')}`, { headers: { range } });
    expect([range, x.status, await x.text(), x.headers.get('content-range')]).toEqual([range, status, text, cr]);
  }
  expect((await t.f(`/v1/datei?pfad=${q('ordner')}`)).status).toBe(400);
  expect((await t.f(`/v1/datei?pfad=${q('nix.txt')}`)).status).toBe(404);
  expect((await t.f(`/v1/datei`)).status).toBe(400);
});

test('Ausbrüche beim Lesen: .., absolut, %2e%2e, Symlinks', async () => {
  const boese = ['../aussen/geheim.txt', `${t.wurzel}/aussen/geheim.txt`, '/etc/passwd', 'ordner/../../aussen/geheim.txt', '%2e%2e/aussen/geheim.txt',
    '..', 'link-datei', 'link-ordner/geheim.txt', 'ordner/../link-datei', 'a.txt\0x'];
  for (const p of boese) {
    for (const route of ['/v1/datei', '/v1/dateien']) {
      for (const pfad of [p, encodeURIComponent(p), '%2e%2e%2faussen%2fgeheim.txt']) {
        const r = await t.f(`${route}?pfad=${pfad}`);
        expect([route, pfad, r.status >= 400, (await r.text()).includes('GEHEIM')]).toEqual([route, pfad, true, false]);
      }
    }
  }
  // die zwei Wege über %2e%2e: einfach kodiert im Query wird zu "../", dann abgelehnt
  expect((await t.f('/v1/datei?pfad=%2e%2e%2faussen%2fgeheim.txt')).status).toBe(403);
  expect((await t.f('/v1/datei?pfad=..%2Faussen%2Fgeheim.txt')).status).toBe(403);
  expect((await t.f('/v1/datei?pfad=/etc/passwd')).status).toBe(403);
  expect((await t.f('/v1/datei?pfad=link-datei')).status).toBe(403);
  expect((await t.f('/v1/dateien?pfad=link-ordner')).status).toBe(403);
});

test('Symlink innerhalb der Wurzel ist erlaubt', async () => {
  expect(await (await t.f(`/v1/datei?pfad=${q('link-innen')}`)).text()).toBe('0123456789');
});

test('Upload legt an, überschreibt nie (2), (3)', async () => {
  const put = (p: string, body: string) => t.f(`/v1/datei?pfad=${q(p)}`, { method: 'PUT', body });
  expect(await (await put('ordner/neu.txt', 'eins')).json()).toEqual({ name: 'neu.txt' });
  expect(await (await put('ordner/neu.txt', 'zwei')).json()).toEqual({ name: 'neu (2).txt' });
  expect(await (await put('ordner/neu.txt', 'drei')).json()).toEqual({ name: 'neu (3).txt' });
  expect(readFileSync(join(t.dateien, 'ordner/neu.txt'), 'utf8')).toBe('eins');
  expect(readFileSync(join(t.dateien, 'ordner/neu (2).txt'), 'utf8')).toBe('zwei');
  expect(await (await put('a.txt', 'neu')).json()).toEqual({ name: 'a (2).txt' });
  expect(readFileSync(join(t.dateien, 'a.txt'), 'utf8')).toBe('0123456789');
  expect(readdirSync(join(t.dateien, 'ordner')).some(n => n.startsWith('.heimherz-'))).toBe(false);
  expect((await put('gibtsnicht/x.txt', 'x')).status).toBe(404);
  expect((await put('', 'x')).status).toBe(403);
});

test('Ausbrüche beim Hochladen: .., absolut, Symlink-Ordner, Symlink als Zielname', async () => {
  const put = (p: string) => t.f(`/v1/datei?pfad=${p}`, { method: 'PUT', body: 'BOESE' });
  for (const p of ['../aussen/x.txt', '/tmp/heimherz-boese.txt', '%2e%2e%2faussen%2fx.txt', q('ordner/../../aussen/x.txt'), q('link-ordner/x.txt'), q('link-ordner/geheim.txt')])
    expect([p, (await put(p)).status]).toEqual([p, 403]);
  expect((await put(q('link-leer'))).status).toBe(200); // Name ist vergeben (Symlink): es entsteht "link-leer (2)", draußen bleibt alles leer
  expect(existsSync(join(aussen(), 'gibtsnicht.txt'))).toBe(false);
  expect(readdirSync(aussen())).toEqual(['geheim.txt']);
  expect(readFileSync(join(aussen(), 'geheim.txt'), 'utf8')).toBe('GEHEIM');
  expect(existsSync('/tmp/heimherz-boese.txt')).toBe(false);
});

test('Papierkorb: Fake-Befehl bekommt den echten Pfad, danach ist die Datei weg', async () => {
  writeFileSync(join(t.dateien, 'weg.txt'), 'x');
  const r = await t.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'weg.txt' }) });
  expect(r.status).toBe(200);
  expect(existsSync(join(t.dateien, 'weg.txt'))).toBe(false);
  expect(readFileSync(join(t.korb, 'weg.txt'), 'utf8')).toBe('x');
  mkdirSync(join(t.dateien, 'leerer-ordner'));
  expect((await t.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'leerer-ordner' }) })).status).toBe(200);
  expect(existsSync(join(t.korb, 'leerer-ordner'))).toBe(true);
});

test('Papierkorb: Ausbrüche, Wurzel, fehlend, Müll', async () => {
  const post = (b: unknown, roh = false) => t.f('/v1/datei/papierkorb', { method: 'POST', body: roh ? String(b) : JSON.stringify(b) });
  for (const pfad of ['../aussen/geheim.txt', '/etc/passwd', 'link-ordner/geheim.txt', 'ordner/../../aussen/geheim.txt'])
    expect([pfad, (await post({ pfad })).status]).toEqual([pfad, 403]);
  expect((await post({ pfad: '' })).status).toBe(403);
  expect((await post({ pfad: '.' })).status).toBe(403);
  expect((await post({ pfad: 'nix.txt' })).status).toBe(404);
  expect((await post({ pfad: 5 })).status).toBe(400);
  expect((await post('kein json', true)).status).toBe(400);
  expect(readFileSync(join(aussen(), 'geheim.txt'), 'utf8')).toBe('GEHEIM');
  expect(existsSync(t.dateien)).toBe(true);
});

test('Papierkorb: ein Symlink nach draußen darf selbst weg, sein Ziel bleibt', async () => {
  const r = await t.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'link-datei' }) });
  expect(r.status).toBe(200);
  expect(readFileSync(join(aussen(), 'geheim.txt'), 'utf8')).toBe('GEHEIM');
});

test('Papierkorb-Befehl fehlt oder scheitert: 500, Datei bleibt', async () => {
  const x = baue({ papierkorb: ['/gibt/es/nicht'] });
  try {
    writeFileSync(join(x.dateien, 'bleibt.txt'), 'x');
    expect((await x.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'bleibt.txt' }) })).status).toBe(500);
    expect(existsSync(join(x.dateien, 'bleibt.txt'))).toBe(true);
  } finally { x.ende(); }
  const y = baue({ papierkorb: ['false'] });
  try {
    writeFileSync(join(y.dateien, 'bleibt.txt'), 'x');
    expect((await y.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'bleibt.txt' }) })).status).toBe(500);
  } finally { y.ende(); }
});

test('Upload ohne Content-Length (Chunked) ist 411, nichts liegt da', async () => {
  const vorher = readdirSync(join(t.dateien, 'ordner')).sort();
  const strom = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(4)); c.close(); } });
  const r = await t.f(`/v1/datei?pfad=${q('ordner/chunk.bin')}`, { method: 'PUT', body: strom as any, duplex: 'half' } as any);
  expect(r.status).toBe(411);
  expect(readdirSync(join(t.dateien, 'ordner')).sort()).toEqual(vorher);
});

test('Upload mit zu langem Namen: 400 statt 500, nichts bleibt liegen', async () => {
  const vorher = readdirSync(join(t.dateien, 'ordner')).sort();
  const r = await t.f(`/v1/datei?pfad=${q('ordner/' + 'a'.repeat(300))}`, { method: 'PUT', body: 'x' });
  expect(r.status).toBe(400);
  expect(await r.text()).toBe('');
  expect(readdirSync(join(t.dateien, 'ordner')).sort()).toEqual(vorher);
});

test('wenig freier Platz: Datei-Upload ist 507, nichts liegt da', async () => {
  const voll = baue({ mindestFrei: Number.MAX_SAFE_INTEGER });
  try {
    expect((await voll.f(`/v1/datei?pfad=${q('x.txt')}`, { method: 'PUT', body: 'x' })).status).toBe(507);
    expect(readdirSync(voll.dateien)).toEqual([]);
    expect((await voll.f('/v1/dateien')).status).toBe(200); // Lesen geht weiter
  } finally { voll.ende(); }
});

test('neue Dateien 0600, neue Ordner 0700', async () => {
  const modus = (p: string) => statSync(p).mode & 0o777;
  const voll = baue();
  try {
    expect((await voll.f(`/v1/datei?pfad=${q('modus.txt')}`, { method: 'PUT', body: 'x' })).status).toBe(200);
    expect(modus(join(voll.dateien, 'modus.txt'))).toBe(0o600);
    expect(modus(voll.dateien)).toBe(0o700);
  } finally { voll.ende(); }
});
