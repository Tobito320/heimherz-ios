// Bitwarden-JSON <-> Heimherz-Tresor (SPEC 7). Reine Umwandlung, kein Zugriff auf Platte oder Netz.
import type { Eintrag, Tresor } from '../lib/zusammenfuehren';

export type Zaehler = { logins: number; notizen: number; uebersprungen: number; anhaenge: number };

const text = (x: unknown) => (typeof x === 'string' ? x : '');
const iso = (x: unknown) => { const t = typeof x === 'string' ? Date.parse(x) : NaN; return new Date(isNaN(t) ? 0 : t).toISOString(); };
const liste = (x: unknown): any[] => (Array.isArray(x) && x.length ? x : []);

// Felder, die Heimherz (noch) nicht kennt, kommen lesbar ans Ende der Notiz und bleiben zusätzlich unverändert am Eintrag (SPEC 5, 7).
const FELDER_KOPF = '--- Felder aus Bitwarden ---';
const FELDER_ENDE = /(^|\n\n)--- Felder aus Bitwarden ---\n[\s\S]*$/;
const ZUSATZ = { 3: ['Karte', 'card'], 4: ['Identität', 'identity'], 5: ['SSH-Schlüssel', 'sshKey'] } as const;
const zeilen = (o: unknown) => Object.entries((o && typeof o === 'object' ? o : {}) as Record<string, unknown>)
  .filter(([, v]) => v !== null && v !== '').map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`);

// Akzeptiert den Export (`{items:[…]}`) wie die Ausgabe von `bw list items` (`[…]`).
export function vonBitwarden(roh: unknown): { eintraege: Eintrag[] } & Zaehler {
  const items: any[] = Array.isArray(roh) ? roh : Array.isArray((roh as any)?.items) ? (roh as any).items : [];
  const z: Zaehler = { logins: 0, notizen: 0, uebersprungen: 0, anhaenge: 0 };
  const eintraege: Eintrag[] = [];
  for (const i of items) {
    if (!i || i.deletedDate || ![1, 2, 3, 4, 5].includes(i.type)) { z.uebersprungen++; continue; }
    const login = i.type === 1;
    const uris = login ? liste(i.login?.uris).filter((u: any) => text(u?.uri)) : [];
    const felder = liste(i.fields);
    const abschnitte = [text(i.notes)];
    if (i.type > 2) abschnitte.push(`--- ${ZUSATZ[i.type as 3 | 4 | 5][0]} ---\n${zeilen(i[ZUSATZ[i.type as 3 | 4 | 5][1]]).join('\n')}`);
    const lesbar = felder.filter(f => f?.value !== null && f?.value !== undefined).map(f => `${text(f.name)}: ${f.value}`);
    if (lesbar.length) abschnitte.push(`${FELDER_KOPF}\n${lesbar.join('\n')}`);
    const e: Eintrag = {
      id: text(i.id) || crypto.randomUUID(), art: login ? 'login' : 'notiz', name: text(i.name),
      benutzer: login ? text(i.login?.username) : '', passwort: login ? text(i.login?.password) : '',
      urls: uris.map((u: any) => text(u.uri)), totp: login ? text(i.login?.totp) : '', notiz: abschnitte.filter(Boolean).join('\n\n'), favorit: !!i.favorite,
      geaendert: iso(i.revisionDate), geloescht: false,
    };
    // Unbekannte Felder bleiben unverändert erhalten; Passkeys (Phase 2) genauso.
    if (login && liste(i.login?.fido2Credentials).length) e.bitwardenFido2 = i.login.fido2Credentials;
    if (felder.length) e.bitwardenFelder = felder;
    if (liste(i.passwordHistory).length) e.bitwardenVerlauf = i.passwordHistory;
    if (uris.some((u: any) => u.match != null)) e.bitwardenUriMatch = uris.map((u: any) => u.match ?? null);
    if (i.reprompt) e.bitwardenReprompt = i.reprompt;
    if (liste(i.attachments).length) z.anhaenge++; // Anhänge können nicht mit, sie bleiben in Bitwarden
    eintraege.push(e);
    login ? z.logins++ : z.notizen++;
  }
  return { eintraege, ...z };
}

export function nachBitwarden(t: Tresor) {
  const items = t.eintraege.filter(e => !e.geloescht).map(e => {
    const felder = Array.isArray(e.bitwardenFelder) && e.bitwardenFelder.length;
    const basis: Record<string, unknown> = { id: e.id, organizationId: null, folderId: null, reprompt: e.bitwardenReprompt ?? 0, name: e.name, notes: (felder ? e.notiz.replace(FELDER_ENDE, '') : e.notiz) || null, favorite: e.favorit, collectionIds: null, revisionDate: e.geaendert, creationDate: e.geaendert, deletedDate: null };
    if (felder) basis.fields = e.bitwardenFelder;
    if (Array.isArray(e.bitwardenVerlauf)) basis.passwordHistory = e.bitwardenVerlauf;
    if (e.art === 'notiz') return { ...basis, type: 2, secureNote: { type: 0 } };
    const match = Array.isArray(e.bitwardenUriMatch) ? e.bitwardenUriMatch : [];
    const login: Record<string, unknown> = { uris: e.urls.map((uri, n) => ({ match: match[n] ?? null, uri })), username: e.benutzer || null, password: e.passwort || null, totp: e.totp || null };
    if (Array.isArray(e.bitwardenFido2)) login.fido2Credentials = e.bitwardenFido2;
    return { ...basis, type: 1, login };
  });
  return { encrypted: false, folders: [], items };
}
