// Tresorschlüssel K und CLI-Token liegen nur als systemd-creds-Datei auf der Platte (Muster claude-bw). Klartext nur im Speicher.
import { chmodSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { hashe, leseGeraete, neuesToken, schreibeGeraete } from '../server/geraete';

export type Creds = {
  verschluessele(name: string, klar: string, datei: string): Promise<void>;
  entschluessele(name: string, datei: string): Promise<string>;
};

async function lauf(argv: string[], stdin?: string): Promise<string> {
  const p = Bun.spawn(argv, { stdin: stdin === undefined ? 'ignore' : 'pipe', stdout: 'pipe', stderr: 'ignore' });
  if (stdin !== undefined) { p.stdin!.write(stdin); await p.stdin!.end(); }
  const [aus, rc] = await Promise.all([new Response(p.stdout).text(), p.exited]);
  if (rc !== 0) throw new Error(`${argv[0]} ${argv[1]} ${argv[2]} schlug fehl (${rc})`);
  return aus;
}

// Klartext geht nur über stdin hinein und stdout hinaus, nie über argv.
export const systemdCreds: Creds = {
  async verschluessele(name, klar, datei) {
    await lauf(['systemd-creds', '--user', 'encrypt', `--name=${name}`, '-', datei], klar);
    chmodSync(datei, 0o600);
  },
  entschluessele: (name, datei) => lauf(['systemd-creds', '--user', 'decrypt', `--name=${name}`, datei, '-']),
};

export const KEY_CRED = 'schluessel.cred', TOKEN_CRED = 'token.cred';
export const KEY_NAME = 'heimherz', TOKEN_NAME = 'heimherz-token';

export async function ladeSchluessel(daten: string, creds: Creds): Promise<Uint8Array> {
  const datei = join(daten, KEY_CRED);
  if (!existsSync(datei)) throw new Error('Kein Schlüssel: erst `heimherz einrichten`');
  const k = new Uint8Array(Buffer.from((await creds.entschluessele(KEY_NAME, datei)).trim(), 'base64url'));
  if (k.length !== 32) throw new Error('Schlüssel unlesbar');
  return k;
}

export async function ladeToken(daten: string, creds: Creds): Promise<string> {
  const datei = join(daten, TOKEN_CRED);
  if (!existsSync(datei)) throw new Error('Kein Gerät-Token: erst `heimherz einrichten`');
  return (await creds.entschluessele(TOKEN_NAME, datei)).trim();
}

// Ordner anlegen, K erzeugen (nie einen vorhandenen überschreiben), CLI als Gerät "pc" eintragen. Mehrfach aufrufbar.
export async function einrichten(o: { daten: string; fotos: string; dateien: string; creds: Creds }): Promise<string[]> {
  mkdirSync(o.daten, { recursive: true, mode: 0o700 });
  chmodSync(o.daten, 0o700);
  mkdirSync(o.fotos, { recursive: true, mode: 0o700 });
  mkdirSync(o.dateien, { recursive: true, mode: 0o700 });
  const meldungen: string[] = [];

  const keyDatei = join(o.daten, KEY_CRED);
  if (existsSync(keyDatei)) meldungen.push('Schlüssel war schon da, unverändert');
  else {
    await o.creds.verschluessele(KEY_NAME, Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url'), keyDatei);
    meldungen.push('Schlüssel angelegt');
  }

  const tokenDatei = join(o.daten, TOKEN_CRED);
  const token = existsSync(tokenDatei) ? await ladeToken(o.daten, o.creds) : neuesToken();
  if (!existsSync(tokenDatei)) await o.creds.verschluessele(TOKEN_NAME, token, tokenDatei);
  const geraete = leseGeraete(o.daten);
  if (!geraete.some(g => g.name === 'pc' && g.hash === hashe(token))) {
    schreibeGeraete(o.daten, [...geraete.filter(g => g.name !== 'pc'), { id: 'pc', name: 'pc', hash: hashe(token), angelegt: new Date().toISOString(), zuletzt: null }]);
    meldungen.push('Gerät pc angelegt');
  } else meldungen.push('Gerät pc war schon da');
  return meldungen;
}
