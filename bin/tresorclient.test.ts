import { afterAll, expect, test } from 'bun:test';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import fx from '../fixtures/bitwarden/export-beispiel.json';
import fxTresor from '../fixtures/tresor/umschlag-1.json';
import { b64, schluessel, verschliesse } from '../lib/umschlag';
import { exportBitwarden, importBitwarden, liste } from './befehle';
import { baueMitCli } from './testhilfe';
import { aendereTresor, DienstFehler, ladeTresor } from './tresorclient';

const c = await baueMitCli();
afterAll(c.ende);
const key = b64(fxTresor.schluessel);
const v = { url: c.url, token: c.token };

test('Tresor mit anderem Format: jeder CLI-Weg bricht ab, nichts wird geschrieben', async () => {
  const neu = await verschliesse({ format: 2, eintraege: [], zukunft: 'x' }, await schluessel(key));
  expect((await c.f('/v1/tresor', { method: 'PUT', headers: { 'if-match': '0' }, body: JSON.stringify(neu) })).status).toBe(200);
  const pfad = join(c.daten, 'tresor/aktuell.json');
  const vorher = readFileSync(pfad, 'utf8');
  const ziel = join(c.wurzel, 'export.json');

  await expect(ladeTresor(v, key)).rejects.toThrow(DienstFehler);
  await expect(aendereTresor(v, key, t => ({ ...t, eintraege: [] }))).rejects.toThrow('Format 2');
  await expect(importBitwarden(c.a, async () => JSON.stringify(fx))).rejects.toThrow(DienstFehler);
  await expect(liste(c.a)).rejects.toThrow(DienstFehler);
  await expect(exportBitwarden(c.a, ziel)).rejects.toThrow(DienstFehler);

  expect(readFileSync(pfad, 'utf8')).toBe(vorher);
  expect(((await (await c.f('/v1/status')).json()) as any).rev).toBe(1);
  expect(existsSync(ziel)).toBe(false); // auch keine halbe Export-Datei
});
