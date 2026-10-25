// Sicherung (SPEC 25): Datei-Format, Aufbewahrung, Wiederherstellungsblatt (W-036). Kein Klartext, K nur im Speicher.
import { b64, istUmschlag, zuB64, type Umschlag } from './umschlag';

export type Blatt = { v: 1; salt: string; nonce: string; daten: string };   // umwickelter K
export type Sicherung = { heimsicherung: 1; datum: string; rev: number; umschlag: Umschlag; wiederherstellung?: Blatt };

export const DATEI = /^heimherz-tresor-(\d{4})-(\d{2})-(\d{2})\.heimsicherung$/;
export const dateiName = (tag: string) => `heimherz-tresor-${tag}.heimsicherung`;   // tag = JJJJ-MM-TT

const strenges = (s: unknown, n: number): s is string => { try { return typeof s === 'string' && b64(s).length === n && zuB64(b64(s)) === s; } catch { return false; } };
export const istBlatt = (x: any): x is Blatt => !!x && x.v === 1 && strenges(x.salt, 16) && strenges(x.nonce, 12) && strenges(x.daten, 48);

export function baueSicherung(umschlag: Umschlag, blatt: Blatt | null, jetzt = new Date()): Sicherung {
  return { heimsicherung: 1, datum: jetzt.toISOString(), rev: umschlag.rev, umschlag, ...(blatt ? { wiederherstellung: blatt } : {}) };
}

// Nur die Form, nie der Inhalt (ohne K nicht prüfbar).
export function leseSicherung(text: string): Sicherung {
  let s: any;
  try { s = JSON.parse(text); } catch { throw new Error('Keine Sicherungsdatei (kein JSON)'); }
  if (s?.heimsicherung !== 1 || !istUmschlag(s.umschlag) || s.rev !== s.umschlag.rev) throw new Error('Keine gültige Heimherz-Sicherung');
  if (s.wiederherstellung !== undefined && !istBlatt(s.wiederherstellung)) throw new Error('Wiederherstellungsblatt in der Sicherung ist ungültig');
  return s;
}

// Welche Dateien bleiben: die letzten `tage` Tage (ab heute rückwärts) und je Monat die jüngste. Fremde Namen kommen nie vor.
export function behalten(namen: string[], heute: string, tage = 14): Set<string> {
  const ok = namen.filter(n => DATEI.test(n)).sort();
  const grenze = new Date(Date.parse(`${heute}T00:00:00Z`) - (tage - 1) * 864e5).toISOString().slice(0, 10);
  const bleibt = new Set(ok.filter(n => n.slice(16, 26) >= grenze));
  const jeMonat = new Map<string, string>();
  for (const n of ok) jeMonat.set(n.slice(16, 23), n);   // sortiert: die letzte je Monat ist die jüngste
  for (const n of jeMonat.values()) bleibt.add(n);
  return bleibt;
}

// --- Wiederherstellungscode: 20 Zufallsbytes als Base32 in Vierergruppen (SPEC 25) ---
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export function codeAlsText(bytes: Uint8Array): string {
  let bits = 0, wert = 0, aus = '';
  for (const b of bytes) { wert = (wert << 8) | b; bits += 8; while (bits >= 5) { aus += ALPHABET[(wert >>> (bits - 5)) & 31]; bits -= 5; } }
  return aus.match(/.{1,4}/g)!.join('-');
}
export function codeAusText(text: string): Uint8Array {
  const roh = text.toUpperCase().replace(/[\s-]/g, '');
  if (!/^[A-Z2-7]{32}$/.test(roh)) throw new Error('Code nicht lesbar: 32 Zeichen A bis Z und 2 bis 7');
  let bits = 0, wert = 0; const aus: number[] = [];
  for (const c of roh) { wert = (wert << 5) | ALPHABET.indexOf(c); bits += 5; if (bits >= 8) { aus.push((wert >>> (bits - 8)) & 255); bits -= 8; } }
  return Uint8Array.from(aus);
}

const INFO = new TextEncoder().encode('heimherz-wiederherstellung-v1');
const AAD_K = new TextEncoder().encode('heimherz-schluessel-v1');

async function umwickelSchluessel(code: Uint8Array, salt: Uint8Array): Promise<CryptoKey> {
  const ikm = await crypto.subtle.importKey('raw', code, 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt, info: INFO }, ikm, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

// Das Handy erzeugt das Blatt; hier nur für den Testvektor (salt und nonce fest) und Tests.
export async function umwickle(k: Uint8Array, code: Uint8Array, salt = crypto.getRandomValues(new Uint8Array(16)), nonce = crypto.getRandomValues(new Uint8Array(12))): Promise<Blatt> {
  const daten = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: AAD_K }, await umwickelSchluessel(code, salt), k);
  return { v: 1, salt: zuB64(salt), nonce: zuB64(nonce), daten: zuB64(daten) };
}

export async function entwickle(blatt: Blatt, code: Uint8Array): Promise<Uint8Array> {
  if (!istBlatt(blatt)) throw new Error('Wiederherstellungsblatt ungültig');
  try {
    const k = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64(blatt.nonce), additionalData: AAD_K }, await umwickelSchluessel(code, b64(blatt.salt)), b64(blatt.daten));
    return new Uint8Array(k);
  } catch { throw new Error('Code passt nicht zu dieser Sicherung'); }
}
