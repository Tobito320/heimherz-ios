import { expect, test } from 'bun:test';
import { b64, istUmschlag, oeffne, schluessel, verschliesse } from './umschlag';
import fx from '../fixtures/tresor/umschlag-1.json';

test('Fixture: fester Schlüssel und Nonce ergeben genau den gespeicherten Umschlag', async () => {
  const k = await schluessel(b64(fx.schluessel));
  expect(await verschliesse(fx.tresor, k, fx.umschlag.rev, b64(fx.umschlag.nonce))).toEqual(fx.umschlag as any);
  expect(await oeffne(fx.umschlag as any, k)).toEqual(fx.tresor);
});

test('rund: verschliessen und oeffnen', async () => {
  const k = await schluessel(crypto.getRandomValues(new Uint8Array(32)));
  const t = { format: 1, eintraege: [] };
  const u = await verschliesse(t, k, 7);
  expect(istUmschlag(u)).toBe(true);
  expect(u.rev).toBe(7);
  expect(await oeffne(u, k)).toEqual(t);
});

test('falscher Schlüssel oder veränderte Daten scheitern', async () => {
  const k = await schluessel(b64(fx.schluessel));
  const fremd = await schluessel(new Uint8Array(32));
  await expect(oeffne(fx.umschlag as any, fremd)).rejects.toThrow();
  const kaputt = { ...fx.umschlag, daten: Buffer.from(b64(fx.umschlag.daten).map((x, i) => (i === 0 ? x ^ 1 : x))).toString('base64') };
  await expect(oeffne(kaputt as any, k)).rejects.toThrow();
});

test('Schlüssel muss 32 Byte haben', () => {
  expect(() => schluessel(new Uint8Array(16))).toThrow();
});

test('istUmschlag prüft nur die Form', () => {
  expect(istUmschlag(fx.umschlag)).toBe(true);
  for (const x of [null, {}, { ...fx.umschlag, v: 2 }, { ...fx.umschlag, rev: -1 }, { ...fx.umschlag, rev: 1.5 }, { ...fx.umschlag, nonce: 'AAAA' }, { ...fx.umschlag, daten: '' }])
    expect(istUmschlag(x)).toBe(false);
});

test('istUmschlag verlangt strenges Base64: Alphabet, Auffüllung, Länge durch 4', () => {
  const n = fx.umschlag.nonce, d = fx.umschlag.daten;
  expect(n.length % 4).toBe(0);
  const schlecht = [
    n.slice(0, 4) + ' ' + n.slice(5), n + '\n', ' ' + n, n.replace(/./, '-'), n.replace(/./, '_'), n.slice(1), n + '=', n + '====', 'A=AA' + n.slice(4),
  ];
  for (const nonce of schlecht) expect([nonce, istUmschlag({ ...fx.umschlag, nonce })]).toEqual([nonce, false]);
  const url = d.replace(/./, '*'), ohneFuell = d.replace(/=+$/, '');
  for (const daten of [url, d + '\n', d.slice(0, 3) + ' ' + d.slice(4), d.slice(1), ...(ohneFuell !== d ? [ohneFuell] : []), d + '=='])
    expect([daten, istUmschlag({ ...fx.umschlag, daten })]).toEqual([daten, false]);
  expect(istUmschlag({ ...fx.umschlag, nonce: 5 })).toBe(false);
});
