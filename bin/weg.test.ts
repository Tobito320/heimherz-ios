import { expect, test } from 'bun:test';
import { alsGeloescht, eintraege, eintragWeg, eintragZurueck } from './befehle';
import { aendereTresor } from './tresorclient';
import { baueMitCli, TESTSCHLUESSEL_B64URL } from './testhilfe';

test('weich löschen behält Felder und setzt Zeit', () => {
  const e = alsGeloescht({ id: 'x', name: 'n', geloescht: false, geaendert: '2026-01-01T00:00:00.000Z' }, new Date('2026-10-27T12:00:00Z'));
  expect(e).toEqual({ id: 'x', name: 'n', geloescht: true, geaendert: '2026-10-27T12:00:00.000Z' });
});

test('weg fragt einmal mit genau den Konten, Nein löscht nichts, zurueck holt es wieder', async () => {
  const c = await baueMitCli();
  const e = (id: string, benutzer: string) => ({ id, art: 'login', name: 'discord.com', benutzer, passwort: 'erfunden', urls: ['https://discord.com'], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00Z', geloescht: false });
  await aendereTresor({ url: c.url, token: c.token }, Buffer.from(TESTSCHLUESSEL_B64URL, 'base64url'), () => ({ format: 1, eintraege: [e('gut', 'a@b.de'), e('kaputt', '')] } as any));
  const fragen: string[] = [];
  await expect(eintragWeg(c.a, ['kaputt'], (t, x) => { fragen.push(`${t}|${x}`); return false; })).rejects.toThrow('nichts gelöscht');
  expect(fragen).toEqual(['Login löschen?|ohne Benutzer · discord.com']);
  await expect(eintragWeg(c.a, ['kaputt', 'gibtsnicht'], () => true)).rejects.toThrow('nichts gelöscht');
  expect(await eintragWeg(c.a, ['kaputt'], () => true)).toBe(true);
  const nach = await eintraege(c.a);
  expect(nach.filter(x => !x.geloescht).map(x => x.id)).toEqual(['gut']);
  expect(await eintragZurueck(c.a, ['kaputt'])).toBe(true);
  expect((await eintraege(c.a)).every(x => !x.geloescht)).toBe(true);
  c.ende();
});
