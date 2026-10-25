// TOTP (RFC 6238) für `heimherz fuell ... code`, gleiche Regeln wie TOTP.swift (Fixture fixtures/totp). Nur WebCrypto.
export type Einstellung = { geheim: string; algorithmus: 'SHA1' | 'SHA256' | 'SHA512'; stellen: number; periode: number };
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function einstellung(roh: string): Einstellung | null {
  const t = roh.trim();
  let geheim = t, algorithmus = 'SHA1', stellen = 6, periode = 30;
  if (/^otpauth:/i.test(t)) {
    let u: URL; try { u = new URL(t); } catch { return null; }
    if (u.host.toLowerCase() !== 'totp') return null;
    geheim = u.searchParams.get('secret') ?? '';
    algorithmus = (u.searchParams.get('algorithm') ?? 'SHA1').toUpperCase();
    stellen = Number(u.searchParams.get('digits') ?? 6); periode = Number(u.searchParams.get('period') ?? 30);
  }
  geheim = geheim.replace(/[\s=-]/g, '').toUpperCase();
  if (!geheim || [...geheim].some(c => !B32.includes(c)) || !['SHA1', 'SHA256', 'SHA512'].includes(algorithmus) || ![6, 7, 8].includes(stellen) || !(periode > 0)) return null;
  return { geheim, algorithmus: algorithmus as Einstellung['algorithmus'], stellen, periode };
}

export async function code(e: Einstellung, jetztMs = Date.now()): Promise<string> {
  let bits = ''; for (const c of e.geheim) bits += B32.indexOf(c).toString(2).padStart(5, '0');
  const k = Uint8Array.from(bits.match(/.{8}/g) ?? [], b => parseInt(b, 2));
  const zaehler = new DataView(new ArrayBuffer(8)); zaehler.setBigUint64(0, BigInt(Math.floor(jetztMs / 1000 / e.periode)));
  const hash = { SHA1: 'SHA-1', SHA256: 'SHA-256', SHA512: 'SHA-512' }[e.algorithmus];
  const key = await crypto.subtle.importKey('raw', k, { name: 'HMAC', hash }, false, ['sign']);
  const h = new Uint8Array(await crypto.subtle.sign('HMAC', key, zaehler.buffer));
  const o = h[h.length - 1] & 15;
  const n = ((h[o] & 0x7f) << 24 | h[o + 1] << 16 | h[o + 2] << 8 | h[o + 3]) % 10 ** e.stellen;
  return String(n).padStart(e.stellen, '0');
}

// Sekunden, die der Code noch gilt
export const restSekunden = (e: Einstellung, jetztMs = Date.now()) => e.periode - Math.floor(jetztMs / 1000) % e.periode;
