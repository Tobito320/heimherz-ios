// Nur für Tests: Temp-Ordner, Testgerät, Dienst auf freiem Port. Nie echte Ordner von Ahmed.
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { hashe, neuesToken, schreibeGeraete } from './geraete';
import { starte, type Optionen } from './dienst';
import { schluessel, verschliesse, b64 } from '../lib/umschlag';
import fx from '../fixtures/tresor/umschlag-1.json';

export type Testdienst = ReturnType<typeof baue>;

export function baue(extra: Partial<Optionen> = {}) {
  const wurzel = mkdtempSync(join(tmpdir(), 'heimherz-test-'));
  const o = { daten: join(wurzel, 'daten'), fotos: join(wurzel, 'fotos'), dateien: join(wurzel, 'dateien'), papierkorb: undefined as string[] | undefined };
  const token = neuesToken();
  schreibeGeraete(o.daten, [{ id: 'g1', name: 'test', hash: hashe(token), angelegt: new Date().toISOString(), zuletzt: null }]);

  // Fake-Papierkorb: verschiebt nach <wurzel>/korb, nie in Ahmeds echten Papierkorb.
  const korb = join(wurzel, 'korb');
  const skript = join(wurzel, 'fake-trash');
  writeFileSync(skript, `#!/bin/sh\nmkdir -p "${korb}" && mv "$1" "${korb}/"\n`);
  chmodSync(skript, 0o755);

  const server = starte({ port: 0, ...o, papierkorb: [skript], mindestFrei: 0, ...extra });
  const url = `http://127.0.0.1:${server.port}`;
  const auth = { authorization: `Bearer ${token}` };
  const f = (pfad: string, init: RequestInit = {}) => fetch(url + pfad, { ...init, headers: { ...auth, ...(init.headers as object) } });
  const ohne = (pfad: string, init: RequestInit = {}) => fetch(url + pfad, init);
  return { wurzel, ...o, korb, server, url, token, auth, f, ohne, ende: () => { server.stop(true); rmSync(wurzel, { recursive: true, force: true }); } };
}

// Echter Umschlag mit dem Test-Schlüssel (SPEC: nur erfundene Daten).
export async function testUmschlag(text = 'x', rev = 0) {
  const k = await schluessel(b64(fx.schluessel));
  return verschliesse({ format: 1, eintraege: [], text }, k, rev);
}
