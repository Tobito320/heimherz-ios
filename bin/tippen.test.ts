import { expect, test } from 'bun:test';
import type { Eintrag } from '../lib/zusammenfuehren';
import { gewaehlt, vorschlaege, wahlen, zeilen } from './tippen';

const e = (x: Partial<Eintrag>): Eintrag => ({ id: 'id-' + Math.random().toString(36).slice(2), art: 'login', name: 'x', benutzer: 'tobi@beispiel.de', passwort: 'erfunden-1', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00Z', geloescht: false, ...x });

test('passende App oben, Code-Zeile nur mit TOTP, ohne Passwort/gelöscht/Notiz raus', () => {
  const l = [e({ name: 'Amazon', urls: ['https://www.amazon.de'] }), e({ name: 'discord.com', urls: ['https://discord.com/login'], totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }),
    e({ name: 'Steam', passwort: '' }), e({ name: 'Alt', geloescht: true }), e({ name: 'Zettel', art: 'notiz' })];
  const w = wahlen(l, 'vesktop Discord | #allgemein');
  expect(w.map(x => `${x.e.name}${x.code ? '+code' : ''}`)).toEqual(['discord.com', 'discord.com+code', 'Amazon']);
  const z = zeilen(w).split('\n');
  expect(z[1]).toBe('2  discord.com  ·  tobi@beispiel.de  ·  Code');
  expect(zeilen(w)).not.toContain('erfunden');
  expect(gewaehlt(w, z[1])?.code).toBe(true);
  expect(gewaehlt(w, '')).toBeUndefined();
});

test('vorschlaege: nur Metadaten, Wörter aus Seite und Name', () => {
  const v = vorschlaege([e({ name: 'Discord Haupt', urls: ['https://www.discord.com/login'], totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }), e({ name: 'leer', passwort: '' })]);
  expect(v).toHaveLength(1);
  expect(v[0].woerter).toEqual(['discord', 'discord haupt']);
  expect(v[0].code).toBe(true);
  expect(JSON.stringify(v)).not.toMatch(/erfunden|GEZD/);
});
