import { afterAll, beforeAll, expect, test } from 'bun:test';
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, renameSync, statSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
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

// ---------- Suche (W-031) ----------

const sekunden = (p: string, s: number) => utimesSync(p, s, s);

function suchBaum() {
  const x = baue();
  const d = x.dateien;
  mkdirSync(join(x.wurzel, 'draussen'), { recursive: true });
  writeFileSync(join(x.wurzel, 'draussen', 'geheim-rechnung.txt'), 'GEHEIM');
  mkdirSync(join(d, 'Buerokratie/2026'), { recursive: true });
  mkdirSync(join(d, 'Fitness'));
  mkdirSync(join(d, 'Ordner Rechnungen'));
  writeFileSync(join(d, 'Buerokratie/Rechnung März.pdf'), 'a');
  writeFileSync(join(d, 'Buerokratie/2026/rechnung-ueber.txt'), 'bb');
  writeFileSync(join(d, 'Buerokratie/Alte Rechnung.pdf'), 'c');
  writeFileSync(join(d, 'Fitness/Plan.txt'), 'p');
  writeFileSync(join(d, 'Überweisung Miete.pdf'), 'u');
  writeFileSync(join(d, 'Straße.txt'), 's');
  writeFileSync(join(d, '.versteckt-rechnung.txt'), 'v');
  writeFileSync(join(d, 'Fitness/.heimherz-x-rechnung.teil'), 't');
  writeFileSync(join(d, 'Fitness/rechnung-halb.teil'), 't');
  symlinkSync(join(x.wurzel, 'draussen'), join(d, 'link-ordner'));
  symlinkSync(join(x.wurzel, 'draussen', 'geheim-rechnung.txt'), join(d, 'link-rechnung.txt'));
  sekunden(join(d, 'Buerokratie/Rechnung März.pdf'), 1_000);
  sekunden(join(d, 'Buerokratie/2026/rechnung-ueber.txt'), 3_000);
  sekunden(join(d, 'Buerokratie/Alte Rechnung.pdf'), 2_000);
  return x;
}
const suche = async (x: ReturnType<typeof baue>, qs: string, pfad?: string) => {
  const r = await x.f(`/v1/dateien/suche?q=${q(qs)}${pfad === undefined ? '' : `&pfad=${q(pfad)}`}`);
  return { status: r.status, liste: r.status === 200 ? await r.json() as any[] : [] };
};

test('Suche: Treffer im Namen, Ordner zuerst, beginnt-mit vor enthält, dann neu vor alt', async () => {
  const x = suchBaum();
  try {
    const { status, liste } = await suche(x, 'rechnung');
    expect(status).toBe(200);
    expect(liste.map(e => e.pfad)).toEqual([
      'Ordner Rechnungen',
      'Buerokratie/2026/rechnung-ueber.txt', // beginnt mit, neuer
      'Buerokratie/Rechnung März.pdf',        // beginnt mit, älter
      'Buerokratie/Alte Rechnung.pdf',        // enthält
    ]);
    expect(liste[0]).toMatchObject({ name: 'Ordner Rechnungen', ordner: true });
    expect(liste[1]).toMatchObject({ name: 'rechnung-ueber.txt', ordner: false, groesse: 2 });
    expect(Date.parse(liste[1].geaendert)).toBe(3_000_000);
    expect(Object.keys(liste[1]).sort()).toEqual(['geaendert', 'groesse', 'name', 'ordner', 'pfad']);
  } finally { x.ende(); }
});

test('Suche: Groß/klein, Umlaute (ä = ae, ß = ss), mehrere Wörter müssen alle vorkommen', async () => {
  const x = suchBaum();
  try {
    const namen = async (qs: string, pfad?: string) => (await suche(x, qs, pfad)).liste.map(e => e.name);
    expect(await namen('RECHNUNG MAERZ')).toEqual(['Rechnung März.pdf']);
    expect(await namen('rechnung märz')).toEqual(['Rechnung März.pdf']);
    expect(await namen('ueberweisung')).toEqual(['Überweisung Miete.pdf']);
    expect(await namen('ÜBERWEISUNG')).toEqual(['Überweisung Miete.pdf']);
    expect(await namen('strasse')).toEqual(['Straße.txt']);
    expect(await namen('STRAẞE')).toEqual(['Straße.txt']);
    expect(await namen('miete ueberweisung')).toEqual(['Überweisung Miete.pdf']);
    expect(await namen('miete rechnung')).toEqual([]);
    expect(await namen('  rechnung   alte  ')).toEqual(['Alte Rechnung.pdf']);
    // Mac-Dateinamen (zerlegtes ä) finden trotzdem
    writeFileSync(join(x.dateien, 'München.txt'), 'm');
    expect(await namen('muenchen')).toEqual(['München.txt']);
  } finally { x.ende(); }
});

test('Suche: ab pfad, Treffer-Pfad bleibt relativ zur Wurzel, versteckte und .teil nie', async () => {
  const x = suchBaum();
  try {
    expect((await suche(x, 'rechnung', 'Buerokratie')).liste.map(e => e.pfad)).toEqual([
      'Buerokratie/2026/rechnung-ueber.txt', 'Buerokratie/Rechnung März.pdf', 'Buerokratie/Alte Rechnung.pdf']);
    expect((await suche(x, 'rechnung', 'Buerokratie/2026')).liste.map(e => e.pfad)).toEqual(['Buerokratie/2026/rechnung-ueber.txt']);
    expect((await suche(x, 'plan', '')).liste.map(e => e.pfad)).toEqual(['Fitness/Plan.txt']);
    const alle = (await suche(x, 'rechnung')).liste.map(e => e.name);
    expect(alle.some(n => n.startsWith('.'))).toBe(false);
    expect((await suche(x, 'heimherz')).liste).toEqual([]);
    expect((await suche(x, 'versteckt')).liste).toEqual([]);
    expect((await suche(x, 'halb')).liste).toEqual([]);
  } finally { x.ende(); }
});

test('Suche: höchstens 200 Treffer', async () => {
  const x = baue();
  try {
    mkdirSync(join(x.dateien, 'viel'));
    for (let i = 0; i < 250; i++) writeFileSync(join(x.dateien, 'viel', `bulk-${i}.txt`), '');
    const { liste } = await suche(x, 'bulk');
    expect(liste.length).toBe(200);
    expect(new Set(liste.map(e => e.pfad)).size).toBe(200);
  } finally { x.ende(); }
});

test('Suche: leere oder zu lange Suche 400, kein q 400, Datei als pfad 400, fehlender pfad 404', async () => {
  const x = suchBaum();
  try {
    expect((await suche(x, '')).status).toBe(400);
    expect((await suche(x, '   ')).status).toBe(400);
    expect((await x.f('/v1/dateien/suche')).status).toBe(400);
    expect((await suche(x, 'a'.repeat(201))).status).toBe(400);
    expect((await suche(x, 'plan', 'Fitness/Plan.txt')).status).toBe(400);
    expect((await suche(x, 'plan', 'gibtsnicht')).status).toBe(404);
    expect((await x.ohne('/v1/dateien/suche?q=plan')).status).toBe(401);
  } finally { x.ende(); }
});

test('Suche: Ausbrüche (.., absolut, Symlink hinaus) sind 403, Symlinks hinaus tauchen nie auf', async () => {
  const x = suchBaum();
  try {
    for (const p of ['..', '../draussen', '/etc', `${x.wurzel}/draussen`, 'Fitness/../../draussen', 'link-ordner', 'a\0b'])
      expect([p, (await suche(x, 'rechnung', p)).status]).toEqual([p, 403]);
    const alle = await suche(x, 'geheim');
    expect(alle.liste).toEqual([]);
    expect(JSON.stringify((await suche(x, 'rechnung')).liste)).not.toContain('geheim');
  } finally { x.ende(); }
});

test('Suche: Symlink innerhalb der Wurzel wird gefunden, aber nicht betreten (keine Schleifen)', async () => {
  const x = baue();
  try {
    mkdirSync(join(x.dateien, 'a'));
    writeFileSync(join(x.dateien, 'a/tief.txt'), 't');
    symlinkSync(x.dateien, join(x.dateien, 'a/schleife'));
    symlinkSync(join(x.dateien, 'a/tief.txt'), join(x.dateien, 'tief-link.txt'));
    expect((await suche(x, 'tief')).liste.map(e => e.pfad).sort()).toEqual(['a/tief.txt', 'tief-link.txt']);
    expect((await suche(x, 'schleife')).liste.map(e => [e.pfad, e.ordner])).toEqual([['a/schleife', true]]);
  } finally { x.ende(); }
});

test('Liste: Ordner tragen anzahl (ohne eigene Temp-Dateien), Dateien nicht', async () => {
  const x = baue();
  try {
    mkdirSync(join(x.dateien, 'o'));
    writeFileSync(join(x.dateien, 'o/1.txt'), '');
    writeFileSync(join(x.dateien, 'o/2.txt'), '');
    writeFileSync(join(x.dateien, 'o/.heimherz-x.teil'), '');
    mkdirSync(join(x.dateien, 'leer'));
    writeFileSync(join(x.dateien, 'f.txt'), '');
    const l = await (await x.f('/v1/dateien')).json() as any[];
    expect(l.find(e => e.name === 'o').anzahl).toBe(2);
    expect(l.find(e => e.name === 'leer').anzahl).toBe(0);
    expect('anzahl' in l.find(e => e.name === 'f.txt')).toBe(false);
  } finally { x.ende(); }
});

// ---------- Vorschau (W-031) ----------

type Aufruf = { art: string; quelle: string; endung: string; px: number; qualitaet: number };
function mitErzeuger(verhalten: (a: Aufruf) => Promise<Uint8Array> | Uint8Array = () => new Uint8Array([0xff, 0xd8, 1, 2, 3])) {
  const aufrufe: Aufruf[] = [];
  let aktiv = 0, hoechstens = 0;
  const erzeuger = async (a: Aufruf & { ziel: string }) => {
    aufrufe.push({ art: a.art, quelle: a.quelle, endung: a.endung, px: a.px, qualitaet: a.qualitaet });
    aktiv++; hoechstens = Math.max(hoechstens, aktiv);
    try { writeFileSync(a.ziel, await verhalten(a)); } finally { aktiv--; }
  };
  const x = baue({ vorschau: { erzeuger } });
  return { x, aufrufe, hoechstens: () => hoechstens };
}
const vor = (x: ReturnType<typeof baue>, pfad: string, px?: string) =>
  x.f(`/v1/dateien/vorschau?pfad=${q(pfad)}${px === undefined ? '' : `&px=${px}`}`);

test('Vorschau: Bild, PDF und Video gehen an den Erzeuger, Antwort ist JPEG, zweites Mal aus dem Cache', async () => {
  const { x, aufrufe } = mitErzeuger();
  try {
    writeFileSync(join(x.dateien, 'Foto.JPG'), 'bild');
    writeFileSync(join(x.dateien, 'a.pdf'), 'pdf');
    writeFileSync(join(x.dateien, 'v.mp4'), 'video');
    for (const n of ['Foto.JPG', 'a.pdf', 'v.mp4']) {
      const r = await vor(x, n);
      expect([n, r.status, r.headers.get('content-type')]).toEqual([n, 200, 'image/jpeg']);
      expect(r.headers.get('x-content-type-options')).toBe('nosniff');
      expect([...new Uint8Array(await r.arrayBuffer())]).toEqual([0xff, 0xd8, 1, 2, 3]);
    }
    expect(aufrufe.map(a => [a.art, a.endung, a.px])).toEqual([['bild', 'jpg', 240], ['pdf', 'pdf', 240], ['video', 'mp4', 240]]);
    expect(aufrufe[0].quelle).toBe(join(realpathSync(x.dateien), 'Foto.JPG'));
    await vor(x, 'Foto.JPG');
    expect(aufrufe.length).toBe(3);
  } finally { x.ende(); }
});

test('Vorschau: Cache-Schlüssel hängt an Pfad, Größe, mtime und px; Dateien 0600, Ordner 0700', async () => {
  const { x, aufrufe } = mitErzeuger();
  try {
    const p = join(x.dateien, 'b.png');
    writeFileSync(p, 'eins');
    sekunden(p, 1_000);
    await vor(x, 'b.png');
    await vor(x, 'b.png', '300');
    expect(aufrufe.map(a => a.px)).toEqual([240, 300]);
    sekunden(p, 2_000);
    await vor(x, 'b.png');
    writeFileSync(p, 'zwei zwei');
    sekunden(p, 2_000);
    await vor(x, 'b.png');
    expect(aufrufe.length).toBe(4);
    const ordner = join(x.daten, 'vorschau');
    expect(statSync(ordner).mode & 0o777).toBe(0o700);
    const dateien = readdirSync(ordner);
    expect(dateien.length).toBe(4);
    expect(dateien.every(n => /^[0-9a-f]{64}\.jpg$/.test(n))).toBe(true);
    expect(dateien.every(n => (statSync(join(ordner, n)).mode & 0o777) === 0o600)).toBe(true);
  } finally { x.ende(); }
});

test('Vorschau: px nur 120 bis 600 ganzzahlig, sonst 400; Standard 240', async () => {
  const { x, aufrufe } = mitErzeuger();
  try {
    writeFileSync(join(x.dateien, 'b.png'), 'x');
    for (const px of ['119', '601', '0', '-5', 'abc', '240.5', '1e2', ''])
      expect([px, (await vor(x, 'b.png', px)).status]).toEqual([px, 400]);
    expect(aufrufe.length).toBe(0);
    expect((await vor(x, 'b.png', '120')).status).toBe(200);
    expect((await vor(x, 'b.png', '600')).status).toBe(200);
    expect(aufrufe.map(a => a.px)).toEqual([120, 600]);
  } finally { x.ende(); }
});

test('Vorschau: andere Typen 404, Ordner 400, fehlend 404, eigene Temp-Datei 404, ohne pfad 400', async () => {
  const { x, aufrufe } = mitErzeuger();
  try {
    writeFileSync(join(x.dateien, 'a.txt'), 'x');
    writeFileSync(join(x.dateien, 'a.docx'), 'x');
    writeFileSync(join(x.dateien, 'ohne'), 'x');
    writeFileSync(join(x.dateien, '.heimherz-1.teil'), 'x');
    writeFileSync(join(x.dateien, '.heimherz-2.png'), 'x');
    mkdirSync(join(x.dateien, 'ordner.png'));
    for (const n of ['a.txt', 'a.docx', 'ohne', '.heimherz-1.teil', '.heimherz-2.png', 'gibtsnicht.png'])
      expect([n, (await vor(x, n)).status]).toEqual([n, 404]);
    expect((await vor(x, 'ordner.png')).status).toBe(400);
    expect((await x.f('/v1/dateien/vorschau')).status).toBe(400);
    expect((await x.ohne('/v1/dateien/vorschau?pfad=a.png')).status).toBe(401);
    expect(aufrufe.length).toBe(0);
  } finally { x.ende(); }
});

test('Vorschau: Ausbrüche (.., absolut, Symlink hinaus) sind 403 und erreichen den Erzeuger nie', async () => {
  const { x, aufrufe } = mitErzeuger();
  try {
    mkdirSync(join(x.wurzel, 'draussen'));
    writeFileSync(join(x.wurzel, 'draussen', 'geheim.png'), 'GEHEIM');
    symlinkSync(join(x.wurzel, 'draussen', 'geheim.png'), join(x.dateien, 'link.png'));
    symlinkSync(join(x.wurzel, 'draussen'), join(x.dateien, 'linkdir'));
    for (const p of ['../draussen/geheim.png', `${x.wurzel}/draussen/geheim.png`, '/etc/passwd', 'a/../../draussen/geheim.png', 'link.png', 'linkdir/geheim.png', 'x.png\0y'])
      expect([p, (await vor(x, p)).status]).toEqual([p, 403]);
    expect(aufrufe.length).toBe(0);
  } finally { x.ende(); }
});

test('Vorschau: Erzeuger scheitert 404 und wird für dieselbe Datei nicht dauernd neu versucht; geänderte Datei darf es erneut', async () => {
  let kaputt = true;
  const { x, aufrufe } = mitErzeuger(() => { if (kaputt) throw new Error('kaputt'); return new Uint8Array([1]); });
  try {
    const p = join(x.dateien, 'k.pdf');
    writeFileSync(p, 'x');
    sekunden(p, 1_000);
    expect((await vor(x, 'k.pdf')).status).toBe(404);
    expect((await vor(x, 'k.pdf')).status).toBe(404);
    expect(aufrufe.length).toBe(1);
    kaputt = false;
    sekunden(p, 2_000);
    expect((await vor(x, 'k.pdf')).status).toBe(200);
    expect(readdirSync(join(x.daten, 'vorschau')).filter(n => n.startsWith('.'))).toEqual([]);
  } finally { x.ende(); }
});

test('Vorschau: Ausgabe über 300 KB wird kleiner versucht, sonst 404; nie größer gespeichert', async () => {
  const gross = new Uint8Array(300 * 1024 + 1);
  const { x, aufrufe } = mitErzeuger(a => a.qualitaet > 60 ? gross : new Uint8Array(300 * 1024));
  try {
    writeFileSync(join(x.dateien, 'g.png'), 'x');
    const r = await vor(x, 'g.png');
    expect(r.status).toBe(200);
    expect((await r.arrayBuffer()).byteLength).toBe(300 * 1024);
    expect(aufrufe.map(a => a.qualitaet)[0]).toBeGreaterThan(60);
    expect(aufrufe.length).toBeGreaterThanOrEqual(2);
  } finally { x.ende(); }
  const z = mitErzeuger(() => gross);
  try {
    writeFileSync(join(z.x.dateien, 'g.png'), 'x');
    expect((await vor(z.x, 'g.png')).status).toBe(404);
    expect(readdirSync(join(z.x.daten, 'vorschau'))).toEqual([]);
  } finally { z.x.ende(); }
  const leerer = mitErzeuger(() => new Uint8Array(0));
  try {
    writeFileSync(join(leerer.x.dateien, 'l.png'), 'x');
    expect((await vor(leerer.x, 'l.png')).status).toBe(404);
  } finally { leerer.x.ende(); }
});

test('Vorschau: höchstens 2 gleichzeitig, gleiche Datei wird zusammengelegt', async () => {
  const { x, aufrufe, hoechstens } = mitErzeuger(async () => { await Bun.sleep(40); return new Uint8Array([7]); });
  try {
    for (let i = 0; i < 6; i++) writeFileSync(join(x.dateien, `p${i}.png`), `x${i}`);
    const rs = await Promise.all([0, 1, 2, 3, 4, 5].map(i => vor(x, `p${i}.png`)));
    expect(rs.map(r => r.status)).toEqual([200, 200, 200, 200, 200, 200]);
    expect(hoechstens()).toBe(2);
    const n = aufrufe.length;
    const doppelt = await Promise.all([vor(x, 'p0.png', '500'), vor(x, 'p0.png', '500'), vor(x, 'p0.png', '500')]);
    expect(doppelt.map(r => r.status)).toEqual([200, 200, 200]);
    expect(aufrufe.length).toBe(n + 1);
  } finally { x.ende(); }
});

test('fuehreAus: Zeitlimit beendet den Prozess, Fehlercode wirft, Erfolg nicht', async () => {
  const { fuehreAus } = await import('./vorschau');
  const t0 = Date.now();
  await expect(fuehreAus(['sleep', '5'], 150)).rejects.toThrow();
  expect(Date.now() - t0).toBeLessThan(2000);
  await expect(fuehreAus(['false'], 1000)).rejects.toThrow();
  await expect(fuehreAus(['/gibt/es/nicht'], 1000)).rejects.toThrow();
  await fuehreAus(['true'], 1000);
});

// Echte Programme (nur wo vorhanden): hier wird bewiesen, dass die Argumente stimmen. Sonst übersprungen, CI braucht sie nicht.
const hat = (...p: string[]) => p.every(n => Bun.which(n));
const jpegKopf = (b: Uint8Array) => b[0] === 0xff && b[1] === 0xd8;
async function echt(erzeugeQuelle: (ordner: string) => Promise<string>) {
  const x = baue();
  try {
    const name = await erzeugeQuelle(x.dateien);
    const r = await vor(x, name, '200');
    expect([name, r.status]).toEqual([name, 200]);
    const b = new Uint8Array(await r.arrayBuffer());
    expect(jpegKopf(b)).toBe(true);
    expect(b.length).toBeLessThanOrEqual(300 * 1024);
    return b;
  } finally { x.ende(); }
}

test.skipIf(!hat('magick'))('echt: Bild mit magick, auch mit Sonderzeichen im Namen', async () => {
  const b = await echt(async o => {
    const name = '[0] -rm %d *?.png';
    Bun.spawnSync(['magick', '-size', '800x600', 'gradient:red-blue', join(o, 'quelle.png')]);
    renameSync(join(o, 'quelle.png'), join(o, name));
    return name;
  });
  expect(b.length).toBeGreaterThan(100);
  // kaputtes Bild: 404 statt Absturz
  const x = baue();
  try {
    writeFileSync(join(x.dateien, 'kaputt.png'), 'kein bild');
    expect((await vor(x, 'kaputt.png')).status).toBe(404);
  } finally { x.ende(); }
});

test.skipIf(!hat('magick', 'pdftoppm'))('echt: PDF erste Seite mit pdftoppm', async () => {
  await echt(async o => {
    const name = 'Dok -x.pdf';
    Bun.spawnSync(['magick', '-size', '600x800', 'xc:white', join(o, 'quelle.pdf')]);
    if (existsSync(join(o, 'quelle.pdf'))) renameSync(join(o, 'quelle.pdf'), join(o, name));
    else writeFileSync(join(o, name), '%PDF-1.0\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 200 300]/Parent 2 0 R>>endobj\ntrailer<</Root 1 0 R>>');
    return name;
  });
});

test.skipIf(!hat('ffmpeg'))('echt: Video ein Bild mit ffmpeg, auch bei Video unter einer Sekunde', async () => {
  for (const sek of ['3', '0.4']) {
    await echt(async o => {
      Bun.spawnSync(['ffmpeg', '-loglevel', 'error', '-f', 'lavfi', '-i', `testsrc=duration=${sek}:size=320x240:rate=10`, join(o, 'quelle.mp4')]);
      renameSync(join(o, 'quelle.mp4'), join(o, '-v.mp4'));
      return '-v.mp4';
    });
  }
});
