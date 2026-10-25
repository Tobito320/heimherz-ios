// `heimherz sicherung` und `heimherz wiederherstellen` (SPEC 25). Die Sicherung ist der Umschlag, wie der Dienst ihn schon verschlüsselt ablegt:
// sie braucht K nie und sieht nie Klartext. Alles Äußere (rclone, Papierkorb, Code-Eingabe) kommt als Parameter herein.
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { baueSicherung, behalten, codeAusText, DATEI, dateiName, entwickle, leseSicherung } from '../lib/sicherung';
import { oeffne, schluessel, type Umschlag } from '../lib/umschlag';
import { zusammenfuehren, type Tresor } from '../lib/zusammenfuehren';
import { Meldung, einrichtenBefehl, type Abh } from './befehle';
import { KEY_CRED, KEY_NAME, ladeSchluessel, ladeToken } from './schluessel';
import { aendereTresor, holeBlatt, holeUmschlag } from './tresorclient';

export const DRIVE_ZIEL = 'gdrive:Heimherz-Sicherung';

export type SicherungAbh = {
  rclone: ((quelle: string, ziel: string) => Promise<void>) | null;   // null = rclone fehlt
  papierkorb: (pfad: string) => Promise<void>;                        // trash-put, nie unlink
  jetzt?: Date;
};

const tagVon = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

// true = alles gut (auch "nichts zu tun"), false = Drive-Teil fehlgeschlagen (lokale Sicherung steht trotzdem).
export async function sicherung(a: Abh, o: SicherungAbh): Promise<boolean> {
  const v = { url: a.dienstUrl, token: await ladeToken(a.daten, a.creds) };
  const u = await holeUmschlag(v);
  if (!u) { a.ausgabe('Noch kein Tresor am PC, nichts zu sichern'); return true; }
  const blatt = await holeBlatt(v);
  const jetzt = o.jetzt ?? new Date(), tag = tagVon(jetzt);
  const dir = join(a.dateien, 'Sicherung');
  mkdirSync(dir, { recursive: true, mode: 0o700 });

  const neueste = readdirSync(dir).filter(n => DATEI.test(n)).sort().at(-1);
  let gleich = false;
  if (neueste) {
    try {
      const s = leseSicherung(readFileSync(join(dir, neueste), 'utf8'));
      gleich = s.rev === u.rev && JSON.stringify(s.wiederherstellung ?? null) === JSON.stringify(blatt) && s.umschlag.daten === u.daten;
    } catch { /* kaputte neueste Datei: neu schreiben */ }
  }
  if (gleich) a.ausgabe(`Unverändert (rev ${u.rev}), keine neue Datei`);
  else {
    const ziel = join(dir, dateiName(tag)), temp = `${ziel}.tmp`;
    writeFileSync(temp, JSON.stringify(baueSicherung(u, blatt, jetzt)), { mode: 0o600 });
    renameSync(temp, ziel);
    a.ausgabe(`Sicherung geschrieben: ${dateiName(tag)} (rev ${u.rev}${blatt ? ', mit Wiederherstellungsblatt' : ''})`);
  }

  const alle = readdirSync(dir), bleibt = behalten(alle, tag);
  for (const n of alle) if (DATEI.test(n) && !bleibt.has(n)) { await o.papierkorb(join(dir, n)); a.ausgabe(`Alte Sicherung in den Papierkorb: ${n}`); }

  if (!o.rclone) { a.ausgabe('Drive: übersprungen (rclone nicht gefunden)'); return false; }
  if (!readdirSync(dir).some(n => DATEI.test(n))) return true;   // nie eine leere Quelle auf Drive spiegeln
  try { await o.rclone(dir, DRIVE_ZIEL); a.ausgabe(`Drive: gespiegelt nach ${DRIVE_ZIEL}`); return true; }
  catch (e) { a.ausgabe(`Drive: fehlgeschlagen (${(e as Error).message})`); return false; }
}

const oeffneMit = async (s: { umschlag: Umschlag }, k: Uint8Array): Promise<Tresor> => {
  const t = await oeffne<Tresor>(s.umschlag, await schluessel(k));
  if (t?.format !== 1) throw new Meldung(`Sicherung hat Format ${t?.format}, dieses heimherz kennt nur 1, nichts geschrieben`);
  return t;
};

// Zusammenführen, nie Überschreiben: neuere Einträge am PC bleiben. Ein vorhandener Schlüssel wird nie ersetzt.
export async function wiederherstellen(a: Abh, datei: string, liesCode: () => Promise<string>): Promise<void> {
  let s;
  try { s = leseSicherung(readFileSync(datei, 'utf8')); } catch (e) { throw new Meldung(`${(e as Error).message}, nichts geändert`); }
  const keyDatei = join(a.daten, KEY_CRED);
  let k: Uint8Array, gesichert: Tresor, neuerSchluessel = false;
  if (existsSync(keyDatei)) {
    k = await ladeSchluessel(a.daten, a.creds);
    try { gesichert = await oeffneMit(s, k); } catch (e) {
      if (e instanceof Meldung) throw e;
      throw new Meldung('Der Schlüssel dieses PCs passt nicht zu dieser Sicherung, nichts geändert');
    }
  } else {
    if (!s.wiederherstellung) throw new Meldung('Dieser PC hat keinen Schlüssel und die Sicherung kein Wiederherstellungsblatt, nichts geändert');
    try { k = await entwickle(s.wiederherstellung, codeAusText(await liesCode())); } catch (e) { throw new Meldung(`${(e as Error).message}, nichts geändert`); }
    try { gesichert = await oeffneMit(s, k); } catch (e) {
      if (e instanceof Meldung) throw e;
      throw new Meldung('Der Code öffnet diese Sicherung nicht, nichts geändert');
    }
    mkdirSync(a.daten, { recursive: true, mode: 0o700 });
    await a.creds.verschluessele(KEY_NAME, Buffer.from(k).toString('base64url'), keyDatei);
    neuerSchluessel = true;
  }
  await einrichtenBefehl({ ...a, ausgabe: () => {} });   // Ordner, Token, Gerät pc (K bleibt, wie er ist)
  await aendereTresor({ url: a.dienstUrl, token: await ladeToken(a.daten, a.creds) }, k, bestehend => zusammenfuehren(bestehend, gesichert));
  if (neuerSchluessel) a.ausgabe('Schlüssel aus dem Code gespeichert (systemd-creds)');
  a.ausgabe(`Sicherung rev ${s.rev} eingespielt: ${gesichert.eintraege.filter(e => !e.geloescht).length} Einträge, neuere am PC bleiben`);
}
