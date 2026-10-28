// `heimherz tippe` (SPEC 29, W-053): Ahmeds Taste füllt in jeder App (Vesktop, Steam, ...), nicht nur in Chrome. Auswahl in fuzzel,
// Werte tippt wtype über stdin ins fokussierte Fenster; nie argv, stdout oder Log.
import type { Eintrag } from '../lib/zusammenfuehren';
import { einstellung } from './totp';

export type Wahl = { e: Eintrag; code: boolean };

const basis = (u: string) => { try { return new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(u) ? u : `https://${u}`).hostname.replace(/^www\./, '').split('.').slice(-2)[0].toLowerCase(); } catch { return ''; } };

// Einträge, deren Seite (discord aus discord.com) oder Name im Fenstertitel oder in der Fensterklasse steht, kommen nach oben.
const woerter = (e: Eintrag) => [...new Set([...e.urls.map(basis), e.name.toLowerCase()])].filter(w => w.length >= 3);
const mitPasswort = (l: Eintrag[]) => l.filter(e => !e.geloescht && e.art === 'login' && e.passwort);

export function wahlen(eintraege: Eintrag[], fenster: string): Wahl[] {
  const f = fenster.toLowerCase();
  const passt = (e: Eintrag) => woerter(e).some(w => f.includes(w));
  const l = mitPasswort(eintraege)
    .sort((a, b) => Number(passt(b)) - Number(passt(a)) || a.name.localeCompare(b.name));
  return l.flatMap(e => einstellung(e.totp) ? [{ e, code: false }, { e, code: true }] : [{ e, code: false }]);
}

// Zeilen für fuzzel; die Nummer vorne macht die Antwort eindeutig, auch bei gleichen Namen.
export const zeilen = (w: Wahl[]) => w.map((x, i) => `${i + 1}  ${x.e.name}${x.e.benutzer ? '  ·  ' + x.e.benutzer : ''}${x.code ? '  ·  Code' : ''}`).join('\n');
export const gewaehlt = (w: Wahl[], antwort: string): Wahl | undefined => w[Number(antwort.trim().split(/\s/)[0]) - 1];

// `heimherz vorschlag` (SPEC 30) für den Lumen-Vorschlag-Dienst: nur Metadaten, nie Passwort oder TOTP-Schlüssel.
export const vorschlaege = (eintraege: Eintrag[]) => mitPasswort(eintraege)
  .map(e => ({ id: e.id, name: e.name, benutzer: e.benutzer, woerter: woerter(e), code: !!einstellung(e.totp) }));
