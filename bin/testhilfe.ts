// Nur für Tests: Fake-Schlüsselablage (kein systemd-creds), Test-Schlüssel aus der Fixture, Dienst in Temp-Ordnern.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import fx from '../fixtures/tresor/umschlag-1.json';
import { baue } from '../server/testhilfe';
import { hashe, leseGeraete, schreibeGeraete } from '../server/geraete';
import type { Abh } from './befehle';
import type { Creds } from './schluessel';

export const fakeCreds: Creds = {
  async verschluessele(name, klar, datei) { writeFileSync(datei, `FAKE:${name}:${Buffer.from(klar).toString('base64')}`, { mode: 0o600 }); },
  async entschluessele(name, datei) {
    const [fake, n, rest] = readFileSync(datei, 'utf8').split(':');
    if (fake !== 'FAKE' || n !== name) throw new Error('falscher Name');
    return Buffer.from(rest, 'base64').toString();
  },
};

export const TESTSCHLUESSEL_B64URL = Buffer.from(fx.schluessel, 'base64').toString('base64url');

// Dienst + CLI-Gerät "pc" (Token im Fake-Creds), Schlüssel = Test-Schlüssel aus der Fixture.
export async function baueMitCli() {
  const t = baue();
  await fakeCreds.verschluessele('heimherz', TESTSCHLUESSEL_B64URL, join(t.daten, 'schluessel.cred'));
  await fakeCreds.verschluessele('heimherz-token', t.token, join(t.daten, 'token.cred'));
  schreibeGeraete(t.daten, [{ id: 'pc', name: 'pc', hash: hashe(t.token), angelegt: new Date().toISOString(), zuletzt: null }]);
  const zeilen: string[] = [];
  const a: Abh = { daten: t.daten, fotos: t.fotos, dateien: t.dateien, dienstUrl: t.url, creds: fakeCreds, ausgabe: z => zeilen.push(z) };
  return { ...t, a, zeilen, text: () => zeilen.join('\n'), leere: () => zeilen.splice(0) };
}

export { existsSync, leseGeraete };
