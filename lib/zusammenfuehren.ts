// Zusammenführen zweier Tresore (SPEC 5), gleiche Regeln wie Gemeinsam/Tresor/Zusammenfuehren.swift.
export type Eintrag = {
  id: string; art: 'login' | 'notiz'; name: string; benutzer: string; passwort: string;
  urls: string[]; totp: string; notiz: string; favorit: boolean; geaendert: string; geloescht: boolean;
  [unbekannt: string]: unknown;
};
export type Tresor = { format: 1; eintraege: Eintrag[]; [unbekannt: string]: unknown };

export const GRABSTEIN_TAGE = 90;
const ms = (iso: string) => Date.parse(iso);
const bytes = (e: Eintrag) => Buffer.from(`${e.passwort}\u0000${e.name}\u0000${e.benutzer}`, 'utf8');

// true, wenn a gegen b gewinnt. Gleichstand: Grabstein gewinnt, dann größere UTF-8-Bytes (deterministisch auf beiden Geräten).
export function gewinnt(a: Eintrag, b: Eintrag): boolean {
  const d = ms(a.geaendert) - ms(b.geaendert);
  if (d !== 0) return d > 0;
  if (a.geloescht !== b.geloescht) return a.geloescht;
  return Buffer.compare(bytes(a), bytes(b)) >= 0;
}

export function zusammenfuehren(a: Tresor, b: Tresor, jetzt = new Date()): Tresor {
  const alle = new Map<string, Eintrag>();
  for (const e of [...a.eintraege, ...b.eintraege]) {
    const da = alle.get(e.id);
    if (!da || gewinnt(e, da)) alle.set(e.id, e);
  }
  const grenze = jetzt.getTime() - GRABSTEIN_TAGE * 864e5;
  const eintraege = [...alle.values()]
    .filter(e => !(e.geloescht && ms(e.geaendert) < grenze))
    .sort((x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0));
  return { ...b, ...a, format: 1, eintraege };
}
