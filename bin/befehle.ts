// Die Befehle des CLI (SPEC 7). Alles Äußere (Schlüssel-Ablage, bw, qrencode, Anzeige, Ausgabe) kommt als Parameter herein.
import { ausCsv, uebernimm } from './apple';
import { Database } from 'bun:sqlite';
import { closeSync, existsSync, openSync, writeSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { zusammenfuehren, type Tresor } from '../lib/zusammenfuehren';
import { leseGeraete, schreibeGeraete } from '../server/geraete';
import { nachBitwarden, vonBitwarden } from './bitwarden';
import { mitTotp } from './fuellen';
import { mitPasswort } from './login';
import { koppeln, type KoppelAbh } from './koppeln';
import { einrichten, ladeSchluessel, ladeToken, type Creds } from './schluessel';
import { aendereTresor, holeStatus, ladeTresor, type Verbindung } from './tresorclient';

export type Abh = {
  daten: string; fotos: string; dateien: string;
  dienstUrl: string;                      // lokaler Dienst, den das CLI selbst anspricht
  creds: Creds;
  ausgabe: (zeile: string) => void;
};

export class Meldung extends Error {}

async function verbindung(a: Abh): Promise<{ v: Verbindung; k: Uint8Array }> {
  return { v: { url: a.dienstUrl, token: await ladeToken(a.daten, a.creds) }, k: await ladeSchluessel(a.daten, a.creds) };
}

export const einrichtenBefehl = async (a: Abh) => { for (const z of await einrichten(a)) a.ausgabe(z); };

export async function koppelnBefehl(a: Abh, name: string, k: Pick<KoppelAbh, 'url' | 'laufzeit' | 'qrencode' | 'zeige' | 'timeoutMs' | 'pollMs' | 'abbruch'>) {
  return koppeln({ ...k, daten: a.daten, name, schluessel: await ladeSchluessel(a.daten, a.creds), ausgabe: a.ausgabe });
}

export async function importBitwarden(a: Abh, bwJson: () => Promise<string>) {
  const { v, k } = await verbindung(a);
  let roh: unknown;
  try { roh = JSON.parse(await bwJson()); } catch (e) {
    if (e instanceof Meldung) throw e;
    throw new Meldung('Bitwarden-Ausgabe nicht lesbar'); // Parser-Fehler können Teile des Inhalts zitieren, darum nie weiterreichen
  }
  const quelle = vonBitwarden(roh);
  const eingang: Tresor = { format: 1, eintraege: quelle.eintraege };
  await aendereTresor(v, k, bestehend => zusammenfuehren(bestehend, eingang));
  a.ausgabe(`${quelle.logins} Logins, ${quelle.notizen} Notizen, ${quelle.uebersprungen} übersprungen`);
  if (quelle.anhaenge) a.ausgabe(`${quelle.anhaenge} Einträge haben Anhänge, die bleiben in Bitwarden`);
}

// CSV aus Apple Passwörter (Mac/Windows) oder Chrome. Die Datei enthält Klartext: nur lesen, nie ausgeben.
export async function importCsv(a: Abh, datei: string) {
  const { v, k } = await verbindung(a);
  let eingang;
  try { eingang = ausCsv(await Bun.file(datei).text()); } catch { throw new Meldung('CSV nicht lesbar oder keine Passwort-Liste (Spalten Username, Password)'); }
  let z = { neu: 0, aktualisiert: 0, gleich: 0 };
  await aendereTresor(v, k, bestehend => { const r = uebernimm(bestehend, eingang); z = r; return r.tresor; });
  a.ausgabe(`${z.neu} neu, ${z.aktualisiert} aktualisiert, ${z.gleich} schon da`);
  a.ausgabe(`Die CSV enthält deine Passwörter im Klartext: jetzt löschen (trash ${datei})`);
}

export async function exportBitwarden(a: Abh, datei: string) {
  if (existsSync(datei)) throw new Meldung('Datei existiert schon, nichts überschrieben');
  const { v, k } = await verbindung(a);
  const { tresor } = await ladeTresor(v, k);
  const fd = openSync(datei, 'wx', 0o600);
  try { writeSync(fd, JSON.stringify(nachBitwarden(tresor), null, 1)); } finally { closeSync(fd); }
  a.ausgabe(`${tresor.eintraege.filter(e => !e.geloescht).length} Einträge nach ${datei} geschrieben (unverschlüsselt, 0600)`);
}

const zelle = (s: string) => s.replace(/[\t\r\n]+/g, ' ');
const host = (u: string) => { try { return new URL(u).hostname; } catch { return u; } };

// Für `heimherz fuell`: Einträge nur in den Speicher, nie ausgeben.
export async function eintraege(a: Abh) {
  const { v, k } = await verbindung(a);
  return (await ladeTresor(v, k)).tresor.eintraege;
}

// `heimherz totp-setzen`: Schlüssel nur in den Speicher und in den Tresor, nie ausgeben.
export async function totpSetzen(a: Abh, id: string, roh: string): Promise<boolean> {
  const { v, k } = await verbindung(a);
  const r = await aendereTresor(v, k, t => {
    const i = t.eintraege.findIndex(e => e.id === id && !e.geloescht);
    if (i < 0) throw new Meldung('Eintrag ist nicht mehr da, nichts gespeichert');
    const eintraege = [...t.eintraege]; eintraege[i] = mitTotp(t.eintraege[i], roh);
    return { ...t, eintraege };
  });
  return r.geschrieben;
}

// `heimherz merke`: neues Passwort nur in den Speicher und in den Tresor, nie ausgeben.
export async function passwortSetzen(a: Abh, id: string, neu: string): Promise<boolean> {
  const { v, k } = await verbindung(a);
  const r = await aendereTresor(v, k, t => {
    const i = t.eintraege.findIndex(e => e.id === id && !e.geloescht);
    if (i < 0) throw new Meldung('Eintrag ist nicht mehr da, nichts gespeichert');
    const eintraege = [...t.eintraege]; eintraege[i] = mitPasswort(t.eintraege[i], neu);
    return { ...t, eintraege };
  });
  return r.geschrieben;
}

// `heimherz weg ID...`: weich löschen wie die App (Felder bleiben, 30 Tage wiederherstellbar).
export const alsGeloescht = <T extends { geloescht: boolean; geaendert: string }>(e: T, jetzt = new Date()): T => ({ ...e, geloescht: true, geaendert: jetzt.toISOString() });
// Löschen braucht Ahmeds Ja in der Notch, auch für Agenten: eine Frage, genau die Konten, "Löschen" oder "Nein" (Ahmed 28.10.2026:
// "one time are you sure you wanna delete the login ... yes no. yes removes it instantly"). Antworten kann nur Ahmed, nicht der Agent.
export function zappyFreigabe(titel: string, text: string): boolean {
  const r = spawnSync('insel', ['bitte', 'erlaubnis', '--titel', titel, '--text', text, '--optionen', 'Löschen,Nein', '--warte', '120'], { encoding: 'utf8' });
  return r.status === 0 && r.stdout.trim() === 'erlauben';   // Knopf Löschen oder gesagtes Ja kommen als erlauben (insel WORT)
}
export async function eintragWeg(a: Abh, ids: string[], frei: (titel: string, text: string) => boolean = zappyFreigabe): Promise<boolean> {
  const { v, k } = await verbindung(a);
  const namen = (await ladeTresor(v, k)).tresor.eintraege.filter(e => ids.includes(e.id) && !e.geloescht).map(e => `${e.benutzer || 'ohne Benutzer'} · ${e.name}`);
  if (namen.length !== ids.length) throw new Meldung('Nicht jede id passt zu einem Eintrag, nichts gelöscht');
  if (!frei(namen.length === 1 ? 'Login löschen?' : `${namen.length} Logins löschen?`, namen.join('\n'))) throw new Meldung('Ahmed hat nicht Löschen gewählt, nichts gelöscht');
  const r = await aendereTresor(v, k, t => {
    for (const id of ids) if (!t.eintraege.some(e => e.id === id && !e.geloescht)) throw new Meldung(`Eintrag ${id} ist nicht da, nichts gespeichert`);
    return { ...t, eintraege: t.eintraege.map(e => ids.includes(e.id) ? alsGeloescht(e) : e) };
  });
  return r.geschrieben;
}

// `heimherz weg --zurueck ID...`: weich gelöschte Einträge wieder da (ohne Frage, nichts geht verloren).
export async function eintragZurueck(a: Abh, ids: string[]): Promise<boolean> {
  const { v, k } = await verbindung(a);
  const r = await aendereTresor(v, k, t => {
    for (const id of ids) if (!t.eintraege.some(e => e.id === id && e.geloescht)) throw new Meldung(`Eintrag ${id} ist nicht gelöscht, nichts gespeichert`);
    return { ...t, eintraege: t.eintraege.map(e => ids.includes(e.id) ? { ...e, geloescht: false, geaendert: new Date().toISOString() } : e) };
  });
  return r.geschrieben;
}

// Nie Passwort, nie TOTP-Geheimnis, nie Notiztext.
export async function liste(a: Abh, suche?: string) {
  const { v, k } = await verbindung(a);
  const s = suche?.toLowerCase();
  a.ausgabe('id\tname\tbenutzer\thosts\ttotp');
  for (const e of (await ladeTresor(v, k)).tresor.eintraege) {
    if (e.geloescht) continue;
    const hosts = [...new Set(e.urls.map(host))].join(',');
    if (s && ![e.name, e.benutzer, hosts].some(x => x.toLowerCase().includes(s))) continue;
    a.ausgabe([e.id, zelle(e.name), zelle(e.benutzer), hosts, e.totp ? 'ja' : 'nein'].join('\t'));
  }
}

function fotosHeute(daten: string): number {
  const pfad = join(daten, 'fotos.db');
  if (!existsSync(pfad)) return 0;
  const db = new Database(pfad, { readonly: true });
  try {
    const mitternacht = new Date(); mitternacht.setHours(0, 0, 0, 0);
    return (db.query('SELECT COUNT(*) AS n FROM fotos WHERE empfangen >= ?').get(mitternacht.toISOString()) as { n: number }).n;
  } catch { return 0; } finally { db.close(); }
}

export async function status(a: Abh) {
  try {
    const s = await holeStatus({ url: a.dienstUrl, token: await ladeToken(a.daten, a.creds) });
    a.ausgabe(`Dienst: läuft (Version ${s.version}), Tresor rev ${s.rev}`);
    a.ausgabe(`Fotos: ${s.fotos} gesamt, ${fotosHeute(a.daten)} heute`);
  } catch (e) {
    a.ausgabe(`Dienst: aus oder nicht erreichbar (${(e as Error).message})`);
  }
  a.ausgabe('Geräte (id, name, zuletzt gemeldet):');
  for (const g of leseGeraete(a.daten)) a.ausgabe(`  ${g.id}\t${zelle(g.name)}\t${g.zuletzt ?? 'noch nie'}`);
}

export function geraetWeg(a: Abh, id: string) {
  const alle = leseGeraete(a.daten);
  const g = alle.find(x => x.id === id);
  if (!g) throw new Meldung(`Kein Gerät mit der id ${id} (heimherz status zeigt sie)`);
  if (g.id === 'pc') throw new Meldung('Das ist das CLI selbst, nicht entfernt');
  schreibeGeraete(a.daten, alle.filter(x => x.id !== id));
  a.ausgabe(`Gerät ${g.name} entfernt, sein Token gilt nicht mehr`);
}
