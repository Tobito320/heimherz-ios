// Dateien-Sync (SPEC 31): Kennungen, Änderungsabfrage, Ersetzen, Umbenennen/Verschieben, Ordner, Papierkorb, Ausbrüche.
import { afterAll, beforeAll, expect, test } from 'bun:test';
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { baue } from './testhilfe';

const t = baue({ sync: { frischMs: 0 } });
afterAll(t.ende);
const q = encodeURIComponent;
const aussen = () => join(t.wurzel, 'aussen');
const P = (p: string) => join(t.dateien, p);

type E = { id: string; eltern: string; name: string; ordner: boolean; groesse: number; geaendert: string; fassung: string };
type Aend = { anker: string; voll: boolean; eintraege: E[]; weg: string[] };
const aend = async (anker?: string): Promise<Aend> => (await t.f(`/v1/dateien/aenderungen${anker === undefined ? '' : `?anker=${q(anker)}`}`)).json() as Promise<Aend>;
const finde = (l: E[], name: string) => l.find(e => e.name === name)!;
const post = (pfad: string, body: unknown, roh = false) => t.f(pfad, { method: 'POST', body: roh ? String(body) : JSON.stringify(body) });
const idVon = async (pfad: string) => { // über die Voll-Liste, Pfad = a/b/c
  let eltern = '';
  let e!: E;
  for (const n of pfad.split('/')) { e = finde((await (await t.f(`/v1/dateien/kinder?id=${q(eltern)}`)).json()) as E[], n); eltern = e.id; }
  return e;
};

beforeAll(() => {
  mkdirSync(aussen(), { recursive: true });
  writeFileSync(join(aussen(), 'geheim.txt'), 'GEHEIM');
  writeFileSync(P('a.txt'), '0123456789');
  mkdirSync(P('ordner'));
  writeFileSync(P('ordner/b.pdf'), 'pdf');
  mkdirSync(P('ordner/tief'));
  writeFileSync(P('ordner/tief/c.txt'), 'c');
  mkdirSync(P('leer'));
  writeFileSync(P('.versteckt'), 'v');
  writeFileSync(P('halb.teil'), 'h');
  writeFileSync(P('.heimherz-x.teil'), 'h');
  symlinkSync(join(aussen(), 'geheim.txt'), P('link-datei'));
  symlinkSync(aussen(), P('link-ordner'));
  symlinkSync(P('a.txt'), P('link-innen'));
});

test('jede neue Route ohne Token: 401', async () => {
  for (const [m, p] of [['GET', '/v1/dateien/aenderungen'], ['GET', '/v1/dateien/kinder'], ['GET', '/v1/dateien/eintrag?id=a-b-c'], ['PUT', '/v1/dateien/neu?eltern=&name=x'], ['POST', '/v1/dateien/ordner'],
    ['POST', '/v1/dateien/umbenennen'], ['PUT', '/v1/dateien/ersetzen?id=a-b-c&fassung=1'], ['POST', '/v1/dateien/papierkorb']]) {
    const r = await t.ohne(p, { method: m, body: m === 'GET' ? undefined : 'x' });
    expect([m, p, r.status, await r.text()]).toEqual([m, p, 401, '']);
  }
});

test('Voll-Liste: alles außer Symlinks, Versteckten und Temp-Dateien; Eltern vor Kindern; Felder stimmen', async () => {
  const a = await aend();
  expect(a.voll).toBe(true);
  expect(a.weg).toEqual([]);
  expect(a.anker).toMatch(/^[0-9a-f]{8}\.\d+$/);
  expect(a.eintraege.map(e => e.name).sort()).toEqual(['a.txt', 'b.pdf', 'c.txt', 'leer', 'ordner', 'tief']);
  const ordner = finde(a.eintraege, 'ordner'), b = finde(a.eintraege, 'b.pdf'), tief = finde(a.eintraege, 'tief'), c = finde(a.eintraege, 'c.txt');
  expect(finde(a.eintraege, 'a.txt')).toMatchObject({ eltern: '', ordner: false, groesse: 10 });
  expect(ordner).toMatchObject({ eltern: '', ordner: true, groesse: 0 });
  expect([b.eltern, tief.eltern, c.eltern]).toEqual([ordner.id, ordner.id, tief.id]);
  expect(Date.parse(b.geaendert)).toBeGreaterThan(0);
  expect(b.fassung).toBe(`${Math.floor(statSync(P("ordner/b.pdf")).mtimeMs)}-3`);
  const pos = (n: string) => a.eintraege.findIndex(e => e.name === n);
  expect(pos('ordner')).toBeLessThan(pos('b.pdf'));
  expect(pos('tief')).toBeLessThan(pos('c.txt'));
  expect(new Set(a.eintraege.map(e => e.id)).size).toBe(a.eintraege.length);
});

test('kurz=1 liefert nur den Anker, ohne Baum', async () => {
  const r = (await (await t.f('/v1/dateien/aenderungen?kurz=1')).json()) as Aend;
  expect([r.eintraege, r.weg]).toEqual([[], []]);
  expect((await aend(r.anker)).eintraege).toEqual([]);
  writeFileSync(P('kurz.txt'), 'k');
  expect((await aend(r.anker)).eintraege.map(e => e.name)).toEqual(['kurz.txt']);
  rmSync(P('kurz.txt'));
});

test('Anker: ohne Änderung leer, neu und geändert erscheinen, gelöscht steht in weg', async () => {
  const a0 = await aend();
  const leer = await aend(a0.anker);
  expect([leer.voll, leer.eintraege, leer.weg, leer.anker]).toEqual([false, [], [], a0.anker]);

  writeFileSync(P('neu.txt'), 'neu');
  const a1 = await aend(a0.anker);
  expect(a1.eintraege.map(e => e.name)).toEqual(['neu.txt']);
  expect(a1.anker).not.toBe(a0.anker);

  writeFileSync(P('neu.txt'), 'neu und länger');
  utimesSync(P('neu.txt'), new Date(), new Date(Date.now() + 5_000));
  const a2 = await aend(a1.anker);
  expect(a2.eintraege.map(e => [e.name, e.groesse])).toEqual([['neu.txt', Buffer.byteLength('neu und länger')]]);
  expect(a2.eintraege[0].id).toBe(a1.eintraege[0].id);

  const id = a2.eintraege[0].id;
  rmSync(P('neu.txt'));
  const a3 = await aend(a2.anker);
  expect([a3.eintraege, a3.weg]).toEqual([[], [id]]);
  // wer vom ersten Anker fragt, sieht das Endergebnis: nichts Neues, die Datei ist nie da gewesen, aber als weg gemeldet (harmlos)
  const von0 = await aend(a0.anker);
  expect(von0.eintraege.map(e => e.name)).toEqual([]);
});

test('Umbenennen und Verschieben am PC (mv) behalten die Kennung', async () => {
  const vorher = await idVon('ordner/b.pdf');
  const a0 = await aend();
  renameSync(P('ordner/b.pdf'), P('ordner/b2.pdf'));
  const a1 = await aend(a0.anker);
  expect(a1.eintraege).toHaveLength(1);
  expect(a1.eintraege[0]).toMatchObject({ id: vorher.id, name: 'b2.pdf', eltern: vorher.eltern });
  expect(a1.weg).toEqual([]);
  renameSync(P('ordner/b2.pdf'), P('leer/b2.pdf'));
  const a2 = await aend(a1.anker);
  expect(a2.eintraege[0]).toMatchObject({ id: vorher.id, name: 'b2.pdf', eltern: (await idVon('leer')).id });
  renameSync(P('leer/b2.pdf'), P('ordner/b.pdf'));
  await aend(a2.anker);
});

test('Anker: fremd, kaputt, aus der Zukunft, zu alt = 410', async () => {
  const a = await aend();
  const [epoche, n] = a.anker.split('.');
  for (const x of ['', 'x', '12345678', `${epoche}.`, `${epoche}.${Number(n) + 1}`, 'ffffffff.0', `${epoche}.-1`, `${epoche}.1e3`, `${epoche}.${n}x`])
    expect([x, (await t.f(`/v1/dateien/aenderungen?anker=${q(x)}`)).status]).toEqual([x, 410]);
});

test('Anker nach Neustart des Dienstes (neue Epoche) = 410, Protokoll zu kurz = 410', async () => {
  const a = await aend();
  const x = baue({ sync: { frischMs: 0 } });
  try {
    expect((await x.f(`/v1/dateien/aenderungen?anker=${q(a.anker)}`)).status).toBe(410);
  } finally { x.ende(); }
  const k = baue({ sync: { frischMs: 0, maxLog: 3 } });
  try {
    const erst = (await (await k.f('/v1/dateien/aenderungen')).json()) as Aend;
    for (let i = 0; i < 5; i++) { writeFileSync(join(k.dateien, `d${i}.txt`), String(i)); await k.f('/v1/dateien/aenderungen'); }
    expect((await k.f(`/v1/dateien/aenderungen?anker=${q(erst.anker)}`)).status).toBe(410);
    const jung = (await (await k.f('/v1/dateien/aenderungen')).json()) as Aend;
    writeFileSync(join(k.dateien, 'noch.txt'), 'x');
    expect((await (await k.f(`/v1/dateien/aenderungen?anker=${q(jung.anker)}`)).json() as Aend).eintraege.map(e => e.name)).toEqual(['noch.txt']);
  } finally { k.ende(); }
});

test('zu viele Einträge: 500 statt eines halben Baums, der wie Löschen aussähe', async () => {
  const x = baue({ sync: { frischMs: 0, maxEintraege: 5 } });
  try {
    for (let i = 0; i < 3; i++) writeFileSync(join(x.dateien, `d${i}`), 'x');
    const ok = (await (await x.f('/v1/dateien/aenderungen')).json()) as Aend;
    expect(ok.eintraege).toHaveLength(3);
    for (let i = 3; i < 8; i++) writeFileSync(join(x.dateien, `d${i}`), 'x');
    expect((await x.f(`/v1/dateien/aenderungen?anker=${q(ok.anker)}`)).status).toBe(500);
    rmSync(join(x.dateien, 'd7'));
    expect((await x.f(`/v1/dateien/aenderungen?anker=${q(ok.anker)}`)).status).toBe(500);
  } finally { x.ende(); }
});

test('Kinder und Eintrag: Wurzel, Unterordner, Pfad für den Download; Müll', async () => {
  const wurzel = (await (await t.f('/v1/dateien/kinder')).json()) as E[];
  expect(wurzel.map(e => e.name)).toEqual(['leer', 'ordner', 'a.txt']);
  expect((await (await t.f('/v1/dateien/kinder?id=')).json() as E[]).length).toBe(3);
  const ordner = finde(wurzel, 'ordner');
  const kinder = (await (await t.f(`/v1/dateien/kinder?id=${q(ordner.id)}`)).json()) as E[];
  expect(kinder.map(e => e.name)).toEqual(['tief', 'b.pdf']);
  expect(kinder.every(e => e.eltern === ordner.id)).toBe(true);
  const b = finde(kinder, 'b.pdf');
  const e = (await (await t.f(`/v1/dateien/eintrag?id=${q(b.id)}`)).json()) as E & { pfad: string };
  expect(e).toMatchObject({ ...b, pfad: 'ordner/b.pdf' });
  expect(await (await t.f(`/v1/datei?pfad=${q(e.pfad)}`)).text()).toBe('pdf');
  expect((await t.f(`/v1/dateien/kinder?id=${q(b.id)}`)).status).toBe(400); // Datei als Ordner
  expect((await t.f('/v1/dateien/kinder?id=1-2-3')).status).toBe(404);
  expect((await t.f('/v1/dateien/eintrag?id=1-2-3')).status).toBe(404);
  expect((await t.f('/v1/dateien/eintrag')).status).toBe(400);
  for (const x of ['../aussen', '/etc', 'ordner', 'a b', 'A-B-C', '%2e%2e', 'x'.repeat(200)])
    expect([x, (await t.f(`/v1/dateien/kinder?id=${q(x)}`)).status]).toEqual([x, 400]);
});

test('Neu: legt an, antwortet mit Eintrag, überschreibt nie, Namen werden geprüft', async () => {
  const put = (eltern: string, name: string, body = 'inhalt') => t.f(`/v1/dateien/neu?eltern=${q(eltern)}&name=${q(name)}`, { method: 'PUT', body });
  const ordner = await idVon('ordner');
  const r = await put(ordner.id, 'neu.txt');
  expect(r.status).toBe(200);
  const e = (await r.json()) as E;
  expect(e).toMatchObject({ name: 'neu.txt', eltern: ordner.id, ordner: false, groesse: 6 });
  expect(readFileSync(P('ordner/neu.txt'), 'utf8')).toBe('inhalt');
  const zwei = (await (await put(ordner.id, 'neu.txt', 'anders')).json()) as E;
  expect(zwei.name).toBe('neu (2).txt');
  expect(zwei.id).not.toBe(e.id);
  expect(readFileSync(P('ordner/neu.txt'), 'utf8')).toBe('inhalt');
  expect((await put('', 'wurzel.txt')).status).toBe(200);
  expect(existsSync(P('wurzel.txt'))).toBe(true);
  for (const n of ['', '.', '..', '../x', 'a/b', '.versteckt', 'x.teil', '.heimherz-x', 'a\0b', 'x'.repeat(201)])
    expect([n, (await put('', n)).status]).toEqual([n, 400]);
  expect((await put('1-2-3', 'x.txt')).status).toBe(404);
  expect((await put('ordner', 'x.txt')).status).toBe(400);
  expect((await t.f('/v1/dateien/neu?eltern=&name=ohne-laenge.txt', { method: 'PUT', body: new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('x')); c.close(); } }) as any, duplex: 'half' } as any)).status).toBe(411);
  expect(existsSync(P('ohne-laenge.txt'))).toBe(false);
  expect(readdirSync(t.dateien).filter(n => n.startsWith('.heimherz-') && n !== '.heimherz-x.teil')).toEqual([]);
  rmSync(P('wurzel.txt')); rmSync(P('ordner/neu.txt')); rmSync(P('ordner/neu (2).txt'));
});

test('Ordner anlegen: 0700, Eintrag, vorhanden 409, falsche Namen und Eltern', async () => {
  const wurzel = await post('/v1/dateien/ordner', { eltern: '', name: 'Neuer Ordner' });
  expect(wurzel.status).toBe(200);
  const e = (await wurzel.json()) as E;
  expect(e).toMatchObject({ name: 'Neuer Ordner', eltern: '', ordner: true });
  expect(statSync(P('Neuer Ordner')).mode & 0o777).toBe(0o700);
  const tief = await post('/v1/dateien/ordner', { eltern: e.id, name: 'innen' });
  expect(((await tief.json()) as E).eltern).toBe(e.id);
  expect((await post('/v1/dateien/ordner', { eltern: '', name: 'Neuer Ordner' })).status).toBe(409);
  expect((await post('/v1/dateien/ordner', { eltern: '', name: 'a.txt' })).status).toBe(409);
  for (const name of ['', '.', '..', 'a/b', '../x', '.versteckt', 'x.teil', 5, null]) expect([name, (await post('/v1/dateien/ordner', { eltern: '', name })).status]).toEqual([name, 400]);
  expect((await post('/v1/dateien/ordner', { eltern: '1-2-3', name: 'x' })).status).toBe(404);
  expect((await post('/v1/dateien/ordner', { eltern: (await idVon('a.txt')).id, name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/ordner', { eltern: '../aussen', name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/ordner', { name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/ordner', 'kein json', true)).status).toBe(400);
  expect((await post('/v1/dateien/ordner', '[]', true)).status).toBe(400);
  expect(readdirSync(aussen())).toEqual(['geheim.txt']);
  rmSync(P('Neuer Ordner'), { recursive: true });
});

test('Umbenennen und Verschieben: Kennung bleibt, nie überschreiben, nie in sich selbst', async () => {
  writeFileSync(P('x1.txt'), 'x1');
  mkdirSync(P('Z'));
  mkdirSync(P('Z/Y'));
  const x1 = await idVon('x1.txt'), zid = await idVon('Z'), yid = await idVon('Z/Y');
  let r = await post('/v1/dateien/umbenennen', { id: x1.id, name: 'x2.txt' });
  expect(r.status).toBe(200);
  expect(await r.json()).toMatchObject({ id: x1.id, name: 'x2.txt', eltern: '' });
  expect([existsSync(P('x1.txt')), readFileSync(P('x2.txt'), 'utf8')]).toEqual([false, 'x1']);
  r = await post('/v1/dateien/umbenennen', { id: x1.id, eltern: zid.id });
  expect(await r.json()).toMatchObject({ id: x1.id, name: 'x2.txt', eltern: zid.id });
  r = await post('/v1/dateien/umbenennen', { id: x1.id, eltern: yid.id, name: 'x3.txt' });
  expect(await r.json()).toMatchObject({ id: x1.id, name: 'x3.txt', eltern: yid.id });
  expect(readFileSync(P('Z/Y/x3.txt'), 'utf8')).toBe('x1');
  r = await post('/v1/dateien/umbenennen', { id: x1.id, eltern: '' });
  expect(await r.json()).toMatchObject({ id: x1.id, name: 'x3.txt', eltern: '' });
  // Ordner samt Inhalt: der Inhalt behält seine Kennungen
  const c = await idVon('ordner/tief/c.txt');
  r = await post('/v1/dateien/umbenennen', { id: (await idVon('ordner/tief')).id, eltern: zid.id, name: 'tief2' });
  expect(r.status).toBe(200);
  expect((await (await t.f(`/v1/dateien/eintrag?id=${q(c.id)}`)).json() as { pfad: string }).pfad).toBe('Z/tief2/c.txt');
  await post('/v1/dateien/umbenennen', { id: (await idVon('Z/tief2')).id, eltern: (await idVon('ordner')).id, name: 'tief' });
  // Überschreiben nie
  writeFileSync(P('y.txt'), 'y');
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, name: 'y.txt' })).status).toBe(409);
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, name: 'ordner' })).status).toBe(409);
  expect([readFileSync(P('y.txt'), 'utf8'), readFileSync(P('x3.txt'), 'utf8')]).toEqual(['y', 'x1']);
  // gleicher Name am gleichen Ort ist kein Konflikt
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, name: 'x3.txt' })).status).toBe(200);
  // Ordner in sich selbst oder in ein Kind
  expect((await post('/v1/dateien/umbenennen', { id: zid.id, eltern: zid.id })).status).toBe(400);
  expect((await post('/v1/dateien/umbenennen', { id: zid.id, eltern: yid.id })).status).toBe(400);
  expect(existsSync(P('Z/Y'))).toBe(true);
  // Datei als Ziel-Ordner, falsche Namen, Wurzel, unbekannt, Müll
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, eltern: (await idVon('a.txt')).id })).status).toBe(400);
  for (const name of ['', '.', '..', 'a/b', '../a', '.versteckt', 'x.teil', 5]) expect([name, (await post('/v1/dateien/umbenennen', { id: x1.id, name })).status]).toEqual([name, 400]);
  expect((await post('/v1/dateien/umbenennen', { id: '', name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/umbenennen', { name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/umbenennen', { id: '1-2-3', name: 'x' })).status).toBe(404);
  expect((await post('/v1/dateien/umbenennen', { id: '../a.txt', name: 'x' })).status).toBe(400);
  expect((await post('/v1/dateien/umbenennen', 'x', true)).status).toBe(400);
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, eltern: '1-2-3' })).status).toBe(404);
  expect((await post('/v1/dateien/umbenennen', { id: x1.id, eltern: '../aussen' })).status).toBe(400);
  expect(readdirSync(aussen())).toEqual(['geheim.txt']);
  rmSync(P('Z'), { recursive: true }); rmSync(P('x3.txt')); rmSync(P('y.txt'));
});

test('Ersetzen: gleiche Fassung ersetzt in derselben Datei (Kennung und Inode bleiben), alte Fassung = 409 und nichts geschieht', async () => {
  writeFileSync(P('doc.txt'), 'eins');
  const e = await idVon('doc.txt');
  const inode = statSync(P('doc.txt')).ino;
  const put = (id: string, fassung: string, body: string) => t.f(`/v1/dateien/ersetzen?id=${q(id)}&fassung=${q(fassung)}`, { method: 'PUT', body });
  let r = await put(e.id, e.fassung, 'zwei und mehr');
  expect(r.status).toBe(200);
  const neu = (await r.json()) as E;
  expect(neu).toMatchObject({ id: e.id, name: 'doc.txt', groesse: 13 });
  expect(neu.fassung).not.toBe(e.fassung);
  expect([readFileSync(P('doc.txt'), 'utf8'), statSync(P('doc.txt')).ino]).toEqual(['zwei und mehr', inode]);
  expect(readdirSync(t.dateien).some(n => n.startsWith('.heimherz-') && n !== '.heimherz-x.teil')).toBe(false);
  // der Handy-Stand ist alt (eins), der PC hat inzwischen geändert (zwei und mehr): Konflikt, die PC-Fassung bleibt
  r = await put(e.id, e.fassung, 'vom Handy');
  expect(r.status).toBe(409);
  expect(await r.json()).toEqual(neu);
  expect(readFileSync(P('doc.txt'), 'utf8')).toBe('zwei und mehr');
  expect(readdirSync(t.dateien).some(n => n.startsWith('.heimherz-') && n !== '.heimherz-x.teil')).toBe(false);
  // Ordner, fehlende Angaben, unbekannt, Müll
  expect((await put((await idVon('ordner')).id, '1', 'x')).status).toBe(400);
  expect((await t.f(`/v1/dateien/ersetzen?id=${q(e.id)}`, { method: 'PUT', body: 'x' })).status).toBe(400);
  expect((await t.f(`/v1/dateien/ersetzen?fassung=1`, { method: 'PUT', body: 'x' })).status).toBe(400);
  expect((await put('1-2-3', '1', 'x')).status).toBe(404);
  expect((await put('../a.txt', '1', 'x')).status).toBe(400);
  expect(readFileSync(P('doc.txt'), 'utf8')).toBe('zwei und mehr');
  rmSync(P('doc.txt'));
});

test('Ersetzen: wenig Platz 507, ohne Länge 411, nichts bleibt liegen', async () => {
  const x = baue({ sync: { frischMs: 0 }, mindestFrei: Number.MAX_SAFE_INTEGER });
  try {
    writeFileSync(join(x.dateien, 'd.txt'), 'alt');
    const e = ((await (await x.f('/v1/dateien/aenderungen')).json()) as Aend).eintraege[0];
    expect((await x.f(`/v1/dateien/ersetzen?id=${q(e.id)}&fassung=${q(e.fassung)}`, { method: 'PUT', body: 'neu' })).status).toBe(507);
    expect(readFileSync(join(x.dateien, 'd.txt'), 'utf8')).toBe('alt');
    expect(readdirSync(x.dateien)).toEqual(['d.txt']);
  } finally { x.ende(); }
  const y = baue({ sync: { frischMs: 0 } });
  try {
    writeFileSync(join(y.dateien, 'd.txt'), 'alt');
    const e = ((await (await y.f('/v1/dateien/aenderungen')).json()) as Aend).eintraege[0];
    const body = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode('neu')); c.close(); } });
    expect((await y.f(`/v1/dateien/ersetzen?id=${q(e.id)}&fassung=${q(e.fassung)}`, { method: 'PUT', body: body as any, duplex: 'half' } as any)).status).toBe(411);
    expect(readFileSync(join(y.dateien, 'd.txt'), 'utf8')).toBe('alt');
    expect(readdirSync(y.dateien)).toEqual(['d.txt']);
  } finally { y.ende(); }
});

test('Papierkorb per Kennung: Datei und Ordner gehen in den Papierkorb, falsche Fassung = 409, nichts wird endgültig gelöscht', async () => {
  writeFileSync(P('weg.txt'), 'x');
  mkdirSync(P('wegordner'));
  writeFileSync(P('wegordner/i.txt'), 'i');
  const w = await idVon('weg.txt'), o = await idVon('wegordner');
  expect((await post('/v1/dateien/papierkorb', { id: w.id, fassung: 'alt-1' })).status).toBe(409);
  expect(existsSync(P('weg.txt'))).toBe(true);
  expect((await post('/v1/dateien/papierkorb', { id: w.id, fassung: w.fassung })).status).toBe(200);
  expect([existsSync(P('weg.txt')), readFileSync(join(t.korb, 'weg.txt'), 'utf8')]).toEqual([false, 'x']);
  expect((await post('/v1/dateien/papierkorb', { id: o.id })).status).toBe(200);
  expect([existsSync(P('wegordner')), readFileSync(join(t.korb, 'wegordner/i.txt'), 'utf8')]).toEqual([false, 'i']);
  expect((await post('/v1/dateien/papierkorb', { id: w.id })).status).toBe(404); // weg
  for (const id of ['', '1-2-3', '../a.txt', 5, undefined]) expect([String(id), (await post('/v1/dateien/papierkorb', { id })).status].slice(1)).toEqual([id === '1-2-3' ? 404 : 400]);
  expect((await post('/v1/dateien/papierkorb', 'x', true)).status).toBe(400);
  expect(existsSync(P('a.txt'))).toBe(true);
  // Papierkorb-Befehl fehlt: 500, Datei bleibt
  const x = baue({ sync: { frischMs: 0 }, papierkorb: ['/gibt/es/nicht'] });
  try {
    writeFileSync(join(x.dateien, 'bleibt.txt'), 'x');
    const e = ((await (await x.f('/v1/dateien/aenderungen')).json()) as Aend).eintraege[0];
    expect((await x.f('/v1/dateien/papierkorb', { method: 'POST', body: JSON.stringify({ id: e.id }) })).status).toBe(500);
    expect(existsSync(join(x.dateien, 'bleibt.txt'))).toBe(true);
  } finally { x.ende(); }
});

test('Ausbrüche mit veraltetem Stand: Ordner wird nach dem Lesen durch einen Symlink nach draußen ersetzt', async () => {
  const x = baue({ sync: { frischMs: 3_600_000 } }); // der Dienst glaubt dem alten Stand: jede Operation muss selbst prüfen
  try {
    mkdirSync(join(x.dateien, 'fall'));
    writeFileSync(join(x.dateien, 'fall/d.txt'), 'drin');
    mkdirSync(join(x.wurzel, 'draussen'));
    writeFileSync(join(x.wurzel, 'draussen/d.txt'), 'AUSSEN');
    const alle = ((await (await x.f('/v1/dateien/aenderungen')).json()) as Aend).eintraege;
    const fall = finde(alle, 'fall'), d = finde(alle, 'd.txt');
    renameSync(join(x.dateien, 'fall'), join(x.dateien, 'fall-alt'));
    symlinkSync(join(x.wurzel, 'draussen'), join(x.dateien, 'fall'));
    const p = (pfad: string, body: unknown) => x.f(pfad, { method: 'POST', body: JSON.stringify(body) });
    const antworten = [
      await x.f(`/v1/dateien/eintrag?id=${q(d.id)}`),
      await x.f(`/v1/dateien/kinder?id=${q(fall.id)}`),
      await p('/v1/dateien/papierkorb', { id: d.id }),
      await p('/v1/dateien/umbenennen', { id: d.id, name: 'geklaut.txt' }),
      await p('/v1/dateien/umbenennen', { id: d.id, eltern: fall.id }),
      await p('/v1/dateien/ordner', { eltern: fall.id, name: 'boese' }),
      await x.f(`/v1/dateien/neu?eltern=${q(fall.id)}&name=boese.txt`, { method: 'PUT', body: 'BOESE' }),
      await x.f(`/v1/dateien/ersetzen?id=${q(d.id)}&fassung=${q(d.fassung)}`, { method: 'PUT', body: 'BOESE' }),
    ];
    // Die erste Operation mit dem veralteten Pfad ist 403 (realpath liegt draußen). Danach liest der Dienst neu und findet die Dinge dort,
    // wo sie wirklich sind (fall-alt): das ist dieselbe Datei im Baum und erlaubt. Der Symlink selbst ist kein Ort mehr, an dem etwas passiert.
    expect(antworten[0].status).toBe(403);
    expect(antworten.every(r => r.status !== 500)).toBe(true);
    expect(readdirSync(join(x.wurzel, 'draussen'))).toEqual(['d.txt']);
    expect(readFileSync(join(x.wurzel, 'draussen/d.txt'), 'utf8')).toBe('AUSSEN');
    expect(existsSync(join(x.wurzel, 'draussen/boese'))).toBe(false);
    expect(existsSync(join(x.wurzel, 'draussen/boese.txt'))).toBe(false);
    expect(existsSync(join(x.wurzel, 'draussen/geklaut.txt'))).toBe(false);
  } finally { x.ende(); }
});

test('Ausbrüche mit veraltetem Stand: jede Operation auf einer Datei im ersetzten Ordner ist beim ersten Versuch 403 und rührt draußen nichts an', async () => {
  const ops: [string, (x: ReturnType<typeof baue>, d: E) => Promise<Response>][] = [
    ['eintrag', (x, d) => x.f(`/v1/dateien/eintrag?id=${q(d.id)}`)],
    ['papierkorb', (x, d) => x.f('/v1/dateien/papierkorb', { method: 'POST', body: JSON.stringify({ id: d.id }) })],
    ['umbenennen', (x, d) => x.f('/v1/dateien/umbenennen', { method: 'POST', body: JSON.stringify({ id: d.id, name: 'geklaut.txt' }) })],
    ['verschieben', (x, d) => x.f('/v1/dateien/umbenennen', { method: 'POST', body: JSON.stringify({ id: d.id, eltern: '' }) })],
    ['ersetzen', (x, d) => x.f(`/v1/dateien/ersetzen?id=${q(d.id)}&fassung=${q(d.fassung)}`, { method: 'PUT', body: 'BOESE' })],
  ];
  for (const [name, op] of ops) {
    const x = baue({ sync: { frischMs: 3_600_000 } });
    try {
      mkdirSync(join(x.dateien, 'fall'));
      writeFileSync(join(x.dateien, 'fall/d.txt'), 'drin');
      mkdirSync(join(x.wurzel, 'draussen'));
      writeFileSync(join(x.wurzel, 'draussen/d.txt'), 'AUSSEN');
      const d = finde(((await (await x.f('/v1/dateien/aenderungen')).json()) as Aend).eintraege, 'd.txt');
      renameSync(join(x.dateien, 'fall'), join(x.dateien, 'fall-alt'));
      symlinkSync(join(x.wurzel, 'draussen'), join(x.dateien, 'fall'));
      expect([name, (await op(x, d)).status]).toEqual([name, 403]);
      expect([name, readdirSync(join(x.wurzel, 'draussen')), readFileSync(join(x.wurzel, 'draussen/d.txt'), 'utf8')]).toEqual([name, ['d.txt'], 'AUSSEN']);
      expect(readFileSync(join(x.dateien, 'fall-alt/d.txt'), 'utf8')).toBe('drin');
    } finally { x.ende(); }
  }
});

test('Ausbrüche: Symlinks und was dahinter liegt tauchen im Sync nie auf; Pfade und Müll statt Kennungen', async () => {
  const a = await aend();
  expect(a.eintraege.map(e => e.name)).not.toContain('geheim.txt');
  expect(a.eintraege.map(e => e.name)).not.toContain('link-datei');
  expect(a.eintraege.map(e => e.name)).not.toContain('link-ordner');
  expect(a.eintraege.map(e => e.name)).not.toContain('link-innen');
  for (const id of ['../aussen', '/etc/passwd', 'link-ordner', 'link-datei', '..', '.', 'a/b', '%2e%2e', 'ordner/b.pdf'])
    for (const pfad of ['/v1/dateien/eintrag', '/v1/dateien/kinder'])
      expect([id, pfad, (await t.f(`${pfad}?id=${q(id)}`)).status]).toEqual([id, pfad, 400]);
  for (const id of ['link-ordner', 'link-datei', 'link-innen']) expect((await post('/v1/dateien/papierkorb', { id })).status).toBe(400);
  expect(existsSync(P('link-datei'))).toBe(true);
  expect(readdirSync(aussen())).toEqual(['geheim.txt']);
});

test('Die bestehenden Routen sind unverändert: Liste, Upload-Antwort, Papierkorb per Pfad', async () => {
  const l = (await (await t.f('/v1/dateien')).json()) as { name: string }[];
  expect(l.map(x => x.name)).toContain('ordner');
  expect(l[0]).not.toHaveProperty('id');
  const r = await t.f(`/v1/datei?pfad=${q('alt-route.txt')}`, { method: 'PUT', body: 'x' });
  expect(await r.json()).toEqual({ name: 'alt-route.txt' });
  expect((await t.f('/v1/datei/papierkorb', { method: 'POST', body: JSON.stringify({ pfad: 'alt-route.txt' }) })).status).toBe(200);
});
