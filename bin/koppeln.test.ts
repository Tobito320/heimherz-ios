import { afterEach, expect, test } from 'bun:test';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { hashe, leseGeraete, schreibeGeraete } from '../server/geraete';
import { koppelUri, koppeln, urlAusTailscale } from './koppeln';

const aufraeumen: string[] = [];
const temp = () => { const d = mkdtempSync(join(tmpdir(), 'heimherz-koppeln-')); aufraeumen.push(d); return d; };
afterEach(() => { for (const d of aufraeumen.splice(0)) rmSync(d, { recursive: true, force: true }); });

const K = new Uint8Array(32).map((_, i) => i + 1);

test('Koppel-URI: url, token und schluessel als b64url, url kodiert', () => {
  const uri = koppelUri('https://tobi-1.tail1234.ts.net', 'TOKEN_-abc', K);
  expect(uri).toBe('heimherz://koppeln?url=https%3A%2F%2Ftobi-1.tail1234.ts.net&token=TOKEN_-abc&schluessel=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA');
  const u = new URL(uri);
  expect(u.protocol).toBe('heimherz:');
  expect(u.searchParams.get('url')).toBe('https://tobi-1.tail1234.ts.net');
  expect(Buffer.from(u.searchParams.get('schluessel')!, 'base64url')).toEqual(Buffer.from(K));
  expect(uri.split('schluessel=')[1]).toMatch(/^[A-Za-z0-9_-]+$/);
});

test('Tailscale-Name ohne Punkt am Ende, https', () => {
  expect(urlAusTailscale(JSON.stringify({ Self: { DNSName: 'tobi-1.tail1234.ts.net.' } }))).toBe('https://tobi-1.tail1234.ts.net');
  expect(() => urlAusTailscale('{}')).toThrow();
});

function aufbau() {
  const daten = temp(), laufzeit = temp();
  schreibeGeraete(daten, [{ id: 'pc', name: 'pc', hash: hashe('x'), angelegt: 'a', zuletzt: null }]);
  const ausgabe: string[] = [];
  let nutzlast = '', rechte = 0, gezeigt = '';
  const abh = {
    daten, laufzeit, name: 'iPhone', url: 'https://pc.example.ts.net', schluessel: K, ausgabe: (z: string) => ausgabe.push(z),
    qrencode: async (n: string, datei: string) => { nutzlast = n; rechte = statSync(datei).mode & 0o777; writeFileSync(datei, 'PNG-INHALT'); },
    zeige: (datei: string) => { gezeigt = datei; },
    pollMs: 10,
  };
  return { daten, laufzeit, ausgabe, abh, info: () => ({ nutzlast, rechte, gezeigt }) };
}

test('Handy meldet sich: Gerät bleibt, PNG ist 0600 und danach weg, nur die festen Zeilen', async () => {
  const s = aufbau();
  const handy = (async () => {
    for (let i = 0; i < 200; i++) {
      const g = leseGeraete(s.daten).find(x => x.name === 'iPhone');
      if (g) { schreibeGeraete(s.daten, leseGeraete(s.daten).map(x => (x.id === g.id ? { ...x, zuletzt: new Date().toISOString() } : x))); return g; }
      await Bun.sleep(5);
    }
  })();
  const ok = await koppeln({ ...s.abh, timeoutMs: 5000 });
  expect(ok).toBe(true);
  const { nutzlast, rechte, gezeigt } = s.info();
  expect(gezeigt).toBe(join(s.laufzeit, 'heimherz/koppeln.png'));
  expect(rechte).toBe(0o600);
  expect(existsSync(gezeigt)).toBe(false);
  expect(s.ausgabe).toEqual(['QR offen, wartet auf Handy', 'Handy gekoppelt']);
  // Nutzlast hat das Token des neuen Geräts, in geraete.json steht nur der Hash
  const token = new URL(nutzlast).searchParams.get('token')!;
  const g = leseGeraete(s.daten).find(x => x.name === 'iPhone')!;
  expect(g.hash).toBe(hashe(token));
  expect(readFileSync(join(s.daten, 'geraete.json'), 'utf8')).not.toContain(token);
  expect((await handy)?.name).toBe('iPhone');
});

test('Zeit um: Gerät wird wieder entfernt, PNG gelöscht, feste Meldung', async () => {
  const s = aufbau();
  const ok = await koppeln({ ...s.abh, timeoutMs: 80 });
  expect(ok).toBe(false);
  expect(leseGeraete(s.daten).map(g => g.name)).toEqual(['pc']);
  expect(existsSync(s.info().gezeigt)).toBe(false);
  expect(s.ausgabe).toEqual(['QR offen, wartet auf Handy', 'Zeit um, Gerät wieder entfernt']);
});

test('Abbruch (Strg-C) räumt genauso auf', async () => {
  const s = aufbau();
  const c = new AbortController();
  setTimeout(() => c.abort(), 50);
  expect(await koppeln({ ...s.abh, timeoutMs: 60_000, abbruch: c.signal })).toBe(false);
  expect(leseGeraete(s.daten).map(g => g.name)).toEqual(['pc']);
  expect(existsSync(s.info().gezeigt)).toBe(false);
});

test('qrencode scheitert: Gerät und Bild werden entfernt, Fehler geht weiter', async () => {
  const s = aufbau();
  await expect(koppeln({ ...s.abh, qrencode: async () => { throw new Error('qrencode kaputt'); } })).rejects.toThrow('qrencode kaputt');
  expect(leseGeraete(s.daten).map(g => g.name)).toEqual(['pc']);
  expect(existsSync(join(s.laufzeit, 'heimherz/koppeln.png'))).toBe(false);
});

test('ohne absolutes Laufzeit-Verzeichnis wird nichts geschrieben und kein Gerät angelegt', async () => {
  const s = aufbau();
  for (const laufzeit of ['', 'relativ/pfad']) await expect(koppeln({ ...s.abh, laufzeit })).rejects.toThrow('XDG_RUNTIME_DIR');
  expect(leseGeraete(s.daten).map(g => g.name)).toEqual(['pc']);
  expect(existsSync('heimherz/koppeln.png')).toBe(false);
});

test('Betrachter wird geschlossen: Zeit um, Strg-C, Erfolg; ein Fehler beim Schließen stört nicht', async () => {
  const zeit = aufbau(), abbruch = aufbau(), erfolg = aufbau();
  const zu = { zeit: 0, abbruch: 0, erfolg: 0 };
  const c = new AbortController();
  setTimeout(() => c.abort(), 30);
  expect(await koppeln({ ...zeit.abh, timeoutMs: 40, zeige: () => () => { zu.zeit++; throw new Error('schon zu'); } })).toBe(false);
  expect(await koppeln({ ...abbruch.abh, timeoutMs: 60_000, abbruch: c.signal, zeige: () => () => { zu.abbruch++; } })).toBe(false);
  setTimeout(() => schreibeGeraete(erfolg.daten, leseGeraete(erfolg.daten).map(g => ({ ...g, zuletzt: g.id === 'pc' ? null : 'jetzt' }))), 30);
  expect(await koppeln({ ...erfolg.abh, timeoutMs: 5000, zeige: () => () => { zu.erfolg++; } })).toBe(true);
  expect(zu).toEqual({ zeit: 1, abbruch: 1, erfolg: 1 });
});

test('Betrachter lässt sich nicht öffnen: Gerät weg, nichts zu schließen', async () => {
  const s = aufbau();
  await expect(koppeln({ ...s.abh, zeige: () => { throw new Error('imv fehlt'); } })).rejects.toThrow('imv fehlt');
  expect(leseGeraete(s.daten).map(g => g.id)).toEqual(['pc']);
});

test('Start räumt verwaiste Geräte ab (nie gemeldet, über 10 Minuten alt); pc und benutzte bleiben', async () => {
  const s = aufbau();
  const vor = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
  const g = (id: string, angelegt: string, zuletzt: string | null) => ({ id, name: id, hash: hashe(id), angelegt, zuletzt });
  schreibeGeraete(s.daten, [g('pc', vor(999), null), g('alt', vor(20), null), g('frisch', vor(2), null), g('benutzt', vor(999), vor(1))]);
  await koppeln({ ...s.abh, timeoutMs: 30 });
  expect(leseGeraete(s.daten).map(x => x.id)).toEqual(['pc', 'frisch', 'benutzt']);
});
