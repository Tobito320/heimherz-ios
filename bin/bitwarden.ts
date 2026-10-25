// Bitwarden-JSON <-> Heimherz-Tresor (SPEC 7). Reine Umwandlung, kein Zugriff auf Platte oder Netz.
import type { Eintrag, Tresor } from '../lib/zusammenfuehren';

export type Zaehler = { logins: number; notizen: number; uebersprungen: number };

const text = (x: unknown) => (typeof x === 'string' ? x : '');
const iso = (x: unknown) => { const t = typeof x === 'string' ? Date.parse(x) : NaN; return new Date(isNaN(t) ? 0 : t).toISOString(); };

// Akzeptiert den Export (`{items:[…]}`) wie die Ausgabe von `bw list items` (`[…]`).
export function vonBitwarden(roh: unknown): { eintraege: Eintrag[] } & Zaehler {
  const items: any[] = Array.isArray(roh) ? roh : Array.isArray((roh as any)?.items) ? (roh as any).items : [];
  const z: Zaehler = { logins: 0, notizen: 0, uebersprungen: 0 };
  const eintraege: Eintrag[] = [];
  for (const i of items) {
    if (!i || i.deletedDate || (i.type !== 1 && i.type !== 2)) { z.uebersprungen++; continue; }
    const login = i.type === 1;
    const e: Eintrag = {
      id: text(i.id) || crypto.randomUUID(), art: login ? 'login' : 'notiz', name: text(i.name),
      benutzer: login ? text(i.login?.username) : '', passwort: login ? text(i.login?.password) : '',
      urls: login ? (i.login?.uris ?? []).map((u: any) => text(u?.uri)).filter(Boolean) : [],
      totp: login ? text(i.login?.totp) : '', notiz: text(i.notes), favorit: !!i.favorite,
      geaendert: iso(i.revisionDate), geloescht: false,
    };
    // Passkeys bleiben unverändert als unbekanntes Feld erhalten (Phase 2).
    if (login && Array.isArray(i.login?.fido2Credentials) && i.login.fido2Credentials.length) e.bitwardenFido2 = i.login.fido2Credentials;
    eintraege.push(e);
    login ? z.logins++ : z.notizen++;
  }
  return { eintraege, ...z };
}

export function nachBitwarden(t: Tresor) {
  const items = t.eintraege.filter(e => !e.geloescht).map(e => {
    const basis = { id: e.id, organizationId: null, folderId: null, reprompt: 0, name: e.name, notes: e.notiz || null, favorite: e.favorit, collectionIds: null, revisionDate: e.geaendert, creationDate: e.geaendert, deletedDate: null };
    if (e.art === 'notiz') return { ...basis, type: 2, secureNote: { type: 0 } };
    const login: Record<string, unknown> = { uris: e.urls.map(uri => ({ match: null, uri })), username: e.benutzer || null, password: e.passwort || null, totp: e.totp || null };
    if (Array.isArray(e.bitwardenFido2)) login.fido2Credentials = e.bitwardenFido2;
    return { ...basis, type: 1, login };
  });
  return { encrypted: false, folders: [], items };
}
