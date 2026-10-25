// Koppeln (SPEC 7): QR mit URL, Token und Schlüssel; wartet, bis das Handy sich meldet. Alles Geheime bleibt im Speicher oder im 0600-PNG.
import { chmodSync, closeSync, existsSync, mkdirSync, openSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { hashe, leseGeraete, neuesToken, schreibeGeraete, type Geraet } from '../server/geraete';

const VERWAIST_MS = 10 * 60_000;

const b64url = (b: Uint8Array) => Buffer.from(b).toString('base64url');

export function koppelUri(url: string, token: string, schluessel: Uint8Array): string {
  return `heimherz://koppeln?url=${encodeURIComponent(url)}&token=${token}&schluessel=${b64url(schluessel)}`;
}

// `tailscale status --json` -> https://<Name im Tailnet>
export function urlAusTailscale(statusJson: string): string {
  const name = String(JSON.parse(statusJson)?.Self?.DNSName ?? '').replace(/\.$/, '');
  if (!name) throw new Error('Tailscale hat keinen Namen für diesen PC (läuft tailscale?)');
  return `https://${name}`;
}

export type KoppelAbh = {
  daten: string; laufzeit: string; name: string; url: string; schluessel: Uint8Array;
  qrencode: (nutzlast: string, datei: string) => Promise<void>;   // Nutzlast nur über stdin
  zeige: (datei: string) => Promise<void | (() => void)> | void | (() => void);   // gibt optional zurück, wie man den Betrachter wieder schließt
  ausgabe: (zeile: string) => void;
  timeoutMs?: number; pollMs?: number; abbruch?: AbortSignal;
};

function loescheBild(datei: string) {
  try { writeFileSync(datei, Buffer.alloc(statSync(datei).size)); } catch { /* war schon weg */ }
  try { unlinkSync(datei); } catch { /* war schon weg */ }
}

export async function koppeln(o: KoppelAbh): Promise<boolean> {
  // Ohne $XDG_RUNTIME_DIR würde das PNG mit Token und Schlüssel in den aktuellen Ordner fallen.
  if (!isAbsolute(o.laufzeit)) throw new Error('XDG_RUNTIME_DIR fehlt, QR wird nicht geschrieben');
  const token = neuesToken();
  const id = crypto.randomUUID().slice(0, 8);
  // Geräte, die vor über 10 Minuten angelegt wurden und sich nie gemeldet haben, sind Reste abgebrochener Koppel-Läufe (das CLI-Gerät "pc" bleibt).
  const verwaist = (g: Geraet) => g.id !== 'pc' && !g.zuletzt && Date.now() - Date.parse(g.angelegt) > VERWAIST_MS;
  schreibeGeraete(o.daten, [...leseGeraete(o.daten).filter(g => !verwaist(g)), { id, name: o.name, hash: hashe(token), angelegt: new Date().toISOString(), zuletzt: null }]);

  const dir = join(o.laufzeit, 'heimherz');
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  chmodSync(dir, 0o700);
  const bild = join(dir, 'koppeln.png');
  let schliesse: void | (() => void);
  try {
    closeSync(openSync(bild, 'w', 0o600)); // erst mit 0600 anlegen, dann schreibt qrencode hinein
    await o.qrencode(koppelUri(o.url, token, o.schluessel), bild);
    chmodSync(bild, 0o600);
    schliesse = await o.zeige(bild);
    o.ausgabe('QR offen, wartet auf Handy');

    const ende = Date.now() + (o.timeoutMs ?? 5 * 60_000);
    while (Date.now() < ende && !o.abbruch?.aborted) {
      if (leseGeraete(o.daten).find(g => g.id === id)?.zuletzt) { o.ausgabe('Handy gekoppelt'); return true; }
      await Bun.sleep(o.pollMs ?? 1000);
    }
    schreibeGeraete(o.daten, leseGeraete(o.daten).filter(g => g.id !== id));
    o.ausgabe('Zeit um, Gerät wieder entfernt');
    return false;
  } catch (e) {
    schreibeGeraete(o.daten, leseGeraete(o.daten).filter(g => g.id !== id));
    throw e;
  } finally {
    try { schliesse?.(); } catch { /* Betrachter war schon zu */ }
    if (existsSync(bild)) loescheBild(bild);
  }
}
