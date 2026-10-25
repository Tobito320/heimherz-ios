// Tresor-Umschlag (SPEC 5): AES-256-GCM, nonce 12 Byte, daten = ciphertext||tag. Swift liest dasselbe mit CryptoKit.
export const AAD = new TextEncoder().encode('heimherz-tresor-v1');

export type Umschlag = { v: 1; rev: number; nonce: string; daten: string };

export const b64 = (s: string) => Uint8Array.from(Buffer.from(s, 'base64'));
export const zuB64 = (b: Uint8Array | ArrayBuffer) => Buffer.from(b instanceof ArrayBuffer ? new Uint8Array(b) : b).toString('base64');

export function schluessel(roh: Uint8Array): Promise<CryptoKey> {
  if (roh.length !== 32) throw new Error('Schlüssel muss 32 Byte haben');
  return crypto.subtle.importKey('raw', roh, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

export async function verschliesse(tresor: unknown, k: CryptoKey, rev = 0, nonce = crypto.getRandomValues(new Uint8Array(12))): Promise<Umschlag> {
  const klar = new TextEncoder().encode(JSON.stringify(tresor));
  const daten = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: AAD }, k, klar);
  return { v: 1, rev, nonce: zuB64(nonce), daten: zuB64(daten) };
}

export async function oeffne<T = unknown>(u: Umschlag, k: CryptoKey): Promise<T> {
  const klar = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b64(u.nonce), additionalData: AAD }, k, b64(u.daten));
  return JSON.parse(new TextDecoder().decode(klar));
}

// Strenges Base64 (Standard-Alphabet, Auffüllung am Ende, Länge durch 4): Buffer.from liest sonst stillschweigend Müll mit.
const strengB64 = (s: unknown): s is string => typeof s === 'string' && s.length % 4 === 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(s);

// Nur die Form, nie der Inhalt: das prüft der Server (er hat keinen Schlüssel).
export function istUmschlag(x: any): x is Umschlag {
  return !!x && x.v === 1 && Number.isInteger(x.rev) && x.rev >= 0
    && strengB64(x.nonce) && b64(x.nonce).length === 12
    && strengB64(x.daten) && b64(x.daten).length >= 16;
}
