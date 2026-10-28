// SPEC 28: Native-Messaging-Host für die Chrome-Erweiterung "Lumen Cloud" (W-051). Chrome startet ihn je Nachricht; Werte gehen nur an die Erweiterung, nie in Log oder argv.
import { readdirSync, readFileSync, readlinkSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { Eintrag } from '../lib/zusammenfuehren';
import { hostVon, protokoll, seite, wertVon, type Was } from './fuellen';
import { ladeSchluessel, ladeToken, systemdCreds } from './schluessel';
import { ladeTresor, type Verbindung } from './tresorclient';
import { einstellung } from './totp';

export const ERWEITERUNG_ID = 'mdjdbdlhjflakglpihdkaipkfnfeding';   // aus "key" in browser/manifest.json
export const HOST_NAME = 'com.lumen.cloud';

type Anfrage = { typ: 'liste'; url: string } | { typ: 'wert'; url: string; id: string; was: Was };

const passend = (l: Eintrag[], url: string) => {
  const h = hostVon(url);
  if (!/^https:\/\//.test(url) || !h) return [];   // nur https: sonst könnte ein Netz dazwischen das Feld lesen
  return l.filter(e => !e.geloescht && e.art === 'login' && e.urls.some(u => { const x = hostVon(u); return x && seite(x) === seite(h); }));
};

export async function antwort(m: Anfrage, l: Eintrag[], jetzt = () => Date.now()): Promise<Record<string, unknown>> {
  if (m?.typ === 'liste') return { eintraege: passend(l, m.url).map(e => ({ id: e.id, name: e.name, benutzer: e.benutzer, passwort: !!e.passwort, code: !!einstellung(e.totp) })) };
  if (m?.typ === 'wert' && ['benutzer', 'passwort', 'code'].includes(m.was)) {
    const e = passend(l, m.url).find(x => x.id === m.id);   // Seite wird hier neu geprüft, nicht der Erweiterung geglaubt
    if (!e) return { fehler: 'Kein passender Eintrag für diese Seite' };
    if (m.was === 'code' && !einstellung(e.totp)) return { fehler: 'Eintrag hat keinen Code' };
    return { wert: await wertVon(e, m.was, jetzt) };
  }
  return { fehler: 'Unbekannte Anfrage' };
}

// Chrome: 4 Byte Länge (little endian), dann JSON.
export function liesNachricht(b: Buffer): unknown {
  if (b.length < 4) throw new Error('Nachricht zu kurz');
  const n = b.readUInt32LE(0);
  if (n > 64 * 1024 || b.length < 4 + n) throw new Error('Nachricht kaputt');
  return JSON.parse(b.subarray(4, 4 + n).toString('utf8'));
}
export function packe(o: unknown): Buffer {
  const j = Buffer.from(JSON.stringify(o), 'utf8'), k = Buffer.alloc(4);
  k.writeUInt32LE(j.length);
  return Buffer.concat([k, j]);
}

// Nur Ahmeds eigenes Chrome: Aufruf von der Erweiterung, Elternprozess ist wirklich Chrome (exe, nicht argv[0]), ohne Fernsteuerung,
// und mit offenen Dateien im echten Profil ~/.config/google-chrome (fängt fremdes HOME ab; environ taugt nicht, Chrome überschreibt es mit dem Prozesstitel).
export function vonAhmedsChrome(argv: string[], eltern: { exe: string; cmdline: string; dateien: string[] }, home: string): string | null {
  if (argv[0] !== `chrome-extension://${ERWEITERUNG_ID}/`) return 'Aufruf nicht von der Lumen-Erweiterung';
  if (eltern.exe !== '/opt/google/chrome/chrome') return 'Elternprozess ist nicht Chrome';
  if (eltern.cmdline.split('\0').some(t => /^--(remote-debugging|user-data-dir|load-extension|headless|disable-extensions-except)/.test(t))) return 'Ferngesteuertes oder fremdes Chrome-Profil';
  if (!eltern.dateien.some(d => d.startsWith(`${home}/.config/google-chrome/`))) return 'Chrome mit fremdem Profilordner';
  return null;
}

// Dauerverbindung (connectNative): Schlüssel und Token einmal laden (systemd-creds kostet ~1 s), den Tresor je Anfrage frisch vom Dienst.
async function main() {
  const e = process.env, state = join(e.XDG_STATE_HOME ?? join(homedir(), '.local/state'), 'heimherz');
  const pp = `/proc/${process.ppid}`;
  let nein: string | null;
  try { nein = vonAhmedsChrome(process.argv.slice(2), { exe: readlinkSync(`${pp}/exe`), cmdline: readFileSync(`${pp}/cmdline`, 'latin1'), dateien: readdirSync(`${pp}/fd`).map(f => { try { return readlinkSync(`${pp}/fd/${f}`); } catch { return ''; } }) }, homedir()); }
  catch { nein = 'Elternprozess nicht lesbar'; }
  const daten = e.HEIMHERZ_DATEN ?? join(homedir(), '.local/share/heimherz');
  let zugang: Promise<{ v: Verbindung; k: Uint8Array }> | null = null;
  const verbinde = () => zugang ??= (async () => ({ v: { url: `http://127.0.0.1:${e.HEIMHERZ_PORT ?? 8790}`, token: await ladeToken(daten, systemdCreds) }, k: await ladeSchluessel(daten, systemdCreds) }))().catch(x => { zugang = null; throw x; });
  if (!nein) verbinde().catch(() => {});   // gleich vorwärmen

  const beantworte = async (m: Anfrage & { nr?: number }) => {
    let raus: Record<string, unknown>;
    if (nein) raus = { fehler: nein };
    else try { const { v, k } = await verbinde(); raus = await antwort(m, (await ladeTresor(v, k)).tresor.eintraege); }
    catch (x) { raus = { fehler: `Lumen Cloud nicht erreichbar: ${String((x as Error).message).slice(0, 80)}` }; }
    if (m?.typ === 'wert') protokoll(state, { host: hostVon(String(m.url ?? '')) || '-', id: m.id, was: `browser ${m.was}`, stufe: 0, modell: 'ahmed-chrome', ok: 'wert' in raus, grund: String(raus.fehler ?? 'Erweiterung') });
    process.stdout.write(packe({ nr: m?.nr, ...raus }));
  };

  let b = Buffer.alloc(0);
  for await (const t of Bun.stdin.stream()) {   // Ende von stdin = Chrome hat die Verbindung zu, Host endet
    b = Buffer.concat([b, Buffer.from(t)]);
    while (b.length >= 4 && b.length >= 4 + b.readUInt32LE(0)) {
      let m: any;
      try { m = liesNachricht(b); } catch (x) { process.stdout.write(packe({ fehler: String((x as Error).message) })); return; }
      b = b.subarray(4 + b.readUInt32LE(0));
      beantworte(m);
    }
  }
}

if (import.meta.main) await main();
