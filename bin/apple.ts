// CSV aus Apple Passwörter (Mac, Windows) oder Chrome -> Heimherz-Tresor. Reine Umwandlung, kein Zugriff auf Platte oder Netz.
import type { Eintrag, Tresor } from '../lib/zusammenfuehren';

// RFC 4180: Felder in "…" dürfen Kommas, Zeilenumbrüche und "" enthalten.
export function csvZeilen(text: string): string[][] {
  const zeilen: string[][] = [];
  let feld = '', zeile: string[] = [], inQ = false;
  const s = text.replace(/^﻿/, '');
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inQ) {
      if (c === '"' && s[i + 1] === '"') { feld += '"'; i++; }
      else if (c === '"') inQ = false;
      else feld += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { zeile.push(feld); feld = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && s[i + 1] === '\n') i++;
      zeile.push(feld); feld = '';
      if (zeile.some(f => f !== '')) zeilen.push(zeile);
      zeile = [];
    } else feld += c;
  }
  zeile.push(feld);
  if (zeile.some(f => f !== '')) zeilen.push(zeile);
  return zeilen;
}

const SPALTEN = { name: ['title', 'name'], url: ['url'], benutzer: ['username'], passwort: ['password'], notiz: ['notes', 'note'], totp: ['otpauth'] };

export function ausCsv(text: string): Eintrag[] {
  const [kopf, ...rest] = csvZeilen(text);
  const k = (kopf ?? []).map(x => x.trim().toLowerCase());
  const pos = Object.fromEntries(Object.entries(SPALTEN).map(([f, namen]) => [f, k.findIndex(x => namen.includes(x))])) as Record<keyof typeof SPALTEN, number>;
  if (pos.passwort < 0 || pos.benutzer < 0) throw new Error('Keine Passwort-CSV (Spalten Username und Password fehlen)');
  const jetzt = new Date(0).toISOString(); // echte Zeit setzt uebernimm
  return rest.map(z => {
    const f = (n: keyof typeof SPALTEN) => (pos[n] >= 0 ? (z[pos[n]] ?? '').trim() : '');
    const notizOnly = !f('benutzer') && !f('passwort') && !f('url');
    return { id: crypto.randomUUID(), art: notizOnly ? 'notiz' : 'login', name: f('name') || f('url'), benutzer: f('benutzer'), passwort: f('passwort'),
      urls: f('url') ? [f('url')] : [], totp: f('totp'), notiz: f('notiz'), favorit: false, geaendert: jetzt, geloescht: false } as Eintrag;
  });
}

const host = (u: string) => { try { return new URL(u.includes('://') ? u : `https://${u}`).hostname.toLowerCase().replace(/^www\./, ''); } catch { return ''; } };
const schluessel = (x: Eintrag) => x.art === 'notiz' ? `notiz\u0000${x.name}\u0000${x.notiz}` : `${x.urls.map(host).sort()[0] ?? x.name.toLowerCase()}\u0000${x.benutzer.toLowerCase()}`;

// Gleicher Host + Benutzer: gleiches Passwort = übersprungen, anderes = aktualisiert (CSV ist die neuere Quelle), altes Passwort in den Verlauf.
export function uebernimm(bestehend: Tresor, eingang: Eintrag[], jetzt = new Date()): { tresor: Tresor; neu: number; aktualisiert: number; gleich: number } {
  const t = jetzt.toISOString();
  const eintraege = bestehend.eintraege.map(x => ({ ...x }));
  const index = new Map<string, Eintrag>();
  for (const x of eintraege) if (!x.geloescht) for (const h of x.art === 'notiz' ? [''] : x.urls.map(host)) index.set(x.art === 'notiz' ? schluessel(x) : `${h}\u0000${x.benutzer.toLowerCase()}`, x);
  let neu = 0, aktualisiert = 0, gleich = 0;
  for (const e of eingang) {
    const da = index.get(schluessel(e));
    if (da && (da.art === 'notiz' || da.passwort === e.passwort) && (!e.totp || da.totp === e.totp)) { gleich++; continue; }
    if (da) {
      if (da.passwort !== e.passwort && da.passwort) da.passwortVerlauf = [{ passwort: da.passwort, bis: t }, ...((da.passwortVerlauf as unknown[]) ?? [])].slice(0, 5);
      da.passwort = e.passwort; if (e.totp) da.totp = e.totp; if (e.notiz && !da.notiz.includes(e.notiz)) da.notiz = da.notiz ? `${da.notiz}\n\n${e.notiz}` : e.notiz;
      da.geaendert = t; aktualisiert++; continue;
    }
    const n = { ...e, geaendert: t };
    eintraege.push(n); index.set(schluessel(n), n); neu++;
  }
  return { tresor: { ...bestehend, eintraege }, neu, aktualisiert, gleich };
}
