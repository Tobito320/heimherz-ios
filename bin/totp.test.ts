import { expect, test } from 'bun:test';
import fx from '../fixtures/totp/rfc6238.json';
import { code, einstellung } from './totp';

test('RFC 6238 Anhang B (gleiche Fixture wie Swift)', async () => {
  for (const v of fx.vektoren) expect(await code({ geheim: v.geheim, algorithmus: v.algorithmus as any, stellen: v.stellen, periode: v.periode }, v.zeit * 1000)).toBe(v.code);
});

test('otpauth-Links und blanke Schlüssel', () => {
  for (const u of fx.uris) expect(einstellung(u.uri)).toEqual({ geheim: u.geheim, algorithmus: u.algorithmus as any, stellen: u.stellen, periode: u.periode });
  expect(einstellung('')).toBeNull();
  expect(einstellung('kein base32 !')).toBeNull();
  expect(einstellung('otpauth://hotp/x?secret=GEZDGNBV')).toBeNull();
});
