import { expect, test } from 'bun:test';
import type { Eintrag } from '../lib/zusammenfuehren';
import { gewaehlt, nutzung, vorschlaege, wahlen, zeilen } from './tippen';

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

test('nutzung: oft benutzte Konten zuerst, nur Ahmed zählt', () => {
  const a = e({ id: 'aaaaaaaa-1', name: 'discord.com', benutzer: '', urls: ['https://discord.com'] }), b = e({ id: 'bbbbbbbb-2', name: 'discord.com', benutzer: 'x@y.de', urls: ['https://discord.com'] });
  const log = ['t\tdiscord.com\tbbbbbbbb\tbrowser passwort\tstufe 0\tahmed-chrome\terlaubt\tErweiterung\t-',
    't\tvesktop\tbbbbbbbb\ttippe\tstufe 0\tahmed\terlaubt\tVorschlag',
    't\tdiscord.com\taaaaaaaa\tpasswort\tstufe 5\tsonnet\terlaubt\tx\t-',
    't\tdiscord.com\taaaaaaaa\tbrowser benutzer\tstufe 0\tahmed-chrome\terlaubt\tErweiterung\t-'].join('\n');
  const n = nutzung(log);
  expect([...n]).toEqual([['bbbbbbbb', 2]]);
  expect(vorschlaege([a, b], n).map(v => v.id)).toEqual(['bbbbbbbb-2', 'aaaaaaaa-1']);
  expect(wahlen([a, b], 'vesktop Discord', n)[0].e.id).toBe('bbbbbbbb-2');
});
