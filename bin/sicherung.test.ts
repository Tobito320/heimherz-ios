import { afterAll, describe, expect, test } from 'bun:test';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import fxW from '../fixtures/sicherung/wiederherstellung-1.json';
import fxT from '../fixtures/tresor/umschlag-1.json';
import { dateiName } from '../lib/sicherung';
import { b64 } from '../lib/umschlag';
import { baue } from '../server/testhilfe';
import { Meldung, type Abh } from './befehle';
import { DRIVE_ZIEL, sicherung, wiederherstellen } from './sicherung';
import { fakeCreds, baueMitCli } from './testhilfe';
import { aendereTresor, ladeTresor } from './tresorclient';
import { einrichtenBefehl } from './befehle';
import { ladeSchluessel } from './schluessel';
import type { Eintrag } from '../lib/zusammenfuehren';

// Köder: auffällige erfundene Geheimnisse; sie dürfen in keiner Datei, Ausgabe oder rclone-Zeile auftauchen.
const KOEDER = ['KOEDER-PW-4711-aXq', 'KOEDER-PW-0815-zZr', 'KOEDER-TOTP-JBSWY3DPEHPK3PXP'];
const eintrag = (id: string, name: string, passwort: string, geaendert: string, extra: Partial<Eintrag> = {}): Eintrag =>
  ({ id, art: 'login', name, benutzer: 'koeder@example.org', passwort, urls: ['https://example.org'], totp: '', notiz: '', favorit: false, geaendert, geloescht: false, ...extra });
const frisch = () => new Date().toISOString();

const c = await baueMitCli();
afterAll(c.ende);
const key = b64(fxT.schluessel);
const v = { url: c.url, token: c.token };
const dir = join(c.dateien, 'Sicherung');

const korb: string[] = [], drive: Array<[string, string]> = [];
const abh = (jetzt: Date, rclone: any = async (q: string, z: string) => { drive.push([q, z]); }) =>
  ({ jetzt, rclone, papierkorb: async (p: string) => { korb.push(p); writeFileSync(p + '.weg', ''); } });
const tag1 = new Date(2026, 9, 26, 10), tag2 = new Date(2026, 9, 27, 10);

await aendereTresor(v, key, () => ({ format: 1, eintraege: [
  eintrag('a1', 'Köder Eins', KOEDER[0], frisch()), eintrag('a2', 'Köder Zwei', KOEDER[1], frisch(), { totp: KOEDER[2] })] }));

const alleTexte = () => readdirSync(dir).filter(n => n.endsWith('.heimsicherung')).map(n => readFileSync(join(dir, n), 'utf8')).join('\n');
const muster = (b: Uint8Array) => [Buffer.from(b).toString('base64'), Buffer.from(b).toString('base64url'), Buffer.from(b).toString('hex')];

describe('heimherz sicherung', () => {
  test('schreibt verschlüsselt: weder Köder noch Schlüssel noch Ausgabe verraten etwas', async () => {
    expect(await sicherung(c.a, abh(tag1))).toBe(true);
    const name = dateiName('2026-10-26');
    expect(readdirSync(dir)).toEqual([name]);
    expect(statSync(join(dir, name)).mode & 0o777).toBe(0o600);
    const roh = alleTexte();
    for (const g of [...KOEDER, 'Köder Eins', 'koeder@example.org', ...muster(key)]) expect(roh).not.toContain(g);
    expect(c.text()).not.toContain('KOEDER');
    expect(c.text()).toContain('Sicherung geschrieben');
    expect(JSON.parse(roh).rev).toBe(((await (await c.f('/v1/status')).json()) as any).rev);
  });

  test('rclone bekommt nur Ordner und festes Ziel, nur .heimsicherung geht mit', async () => {
    expect(drive).toEqual([[dir, DRIVE_ZIEL]]);
    expect(DRIVE_ZIEL).toBe('gdrive:Heimherz-Sicherung');
  });

  test('unverändert: keine neue Datei, Datei bleibt byte-gleich', async () => {
    const vorher = readFileSync(join(dir, dateiName('2026-10-26')), 'utf8');
    c.leere();
    await sicherung(c.a, abh(tag2));
    expect(readdirSync(dir)).toEqual([dateiName('2026-10-26')]);
    expect(readFileSync(join(dir, dateiName('2026-10-26')), 'utf8')).toBe(vorher);
    expect(c.text()).toContain('Unverändert');
  });

  test('geänderte rev: neue Datei am neuen Tag, am selben Tag wird ersetzt', async () => {
    await aendereTresor(v, key, t => ({ ...t, eintraege: [...t.eintraege, eintrag('a3', 'Drei', KOEDER[0], frisch())] }));
    await sicherung(c.a, abh(tag2));
    expect(readdirSync(dir).sort()).toEqual([dateiName('2026-10-26'), dateiName('2026-10-27')]);
    const rev2 = JSON.parse(readFileSync(join(dir, dateiName('2026-10-27')), 'utf8')).rev;
    await aendereTresor(v, key, t => ({ ...t, eintraege: [...t.eintraege, eintrag('a4', 'Vier', KOEDER[1], frisch())] }));
    await sicherung(c.a, abh(tag2));
    expect(readdirSync(dir).sort()).toHaveLength(2);
    expect(JSON.parse(readFileSync(join(dir, dateiName('2026-10-27')), 'utf8')).rev).toBe(rev2 + 1);
    expect(alleTexte()).not.toContain(KOEDER[0]);
  });

  test('neues Wiederherstellungsblatt allein löst eine neue Sicherung aus', async () => {
    const vorher = JSON.parse(readFileSync(join(dir, dateiName('2026-10-27')), 'utf8'));
    expect(vorher.wiederherstellung).toBeUndefined();
    expect((await c.f('/v1/wiederherstellung', { method: 'PUT', body: JSON.stringify(fxW.blatt) })).status).toBe(200);
    await sicherung(c.a, abh(tag2));
    const nachher = JSON.parse(readFileSync(join(dir, dateiName('2026-10-27')), 'utf8'));
    expect(nachher.wiederherstellung).toEqual(fxW.blatt);
    expect(nachher.rev).toBe(vorher.rev);
  });

  test('Aufbewahrung: alte Dateien in den Papierkorb, Fremdes bleibt, 14 Tage und je Monat', async () => {
    for (let i = 3; i < 40; i++) writeFileSync(join(dir, dateiName(new Date(Date.UTC(2026, 9, 27) - i * 864e5).toISOString().slice(0, 10))), '{}');
    writeFileSync(join(dir, 'notiz.txt'), 'x');
    korb.length = 0;
    await sicherung(c.a, abh(tag2));
    const namen = readdirSync(dir);
    expect(namen).toContain('notiz.txt');
    expect(korb.every(p => /heimherz-tresor-\d{4}-\d{2}-\d{2}\.heimsicherung$/.test(p))).toBe(true);
    expect(korb).toContain(join(dir, dateiName('2026-10-05')));
    expect(korb).not.toContain(join(dir, dateiName('2026-10-20')));
    expect(korb).not.toContain(join(dir, dateiName('2026-09-30')));   // jüngste im September
    expect(korb).toContain(join(dir, dateiName('2026-09-29')));
  });

  test('rclone fehlt oder scheitert: lokale Sicherung steht, Ergebnis false, Meldung ohne Geheimnis', async () => {
    c.leere();
    expect(await sicherung(c.a, abh(tag2, null))).toBe(false);
    expect(c.text()).toContain('rclone nicht gefunden');
    c.leere();
    expect(await sicherung(c.a, abh(tag2, async () => { throw new Error('Remote gdrive: fehlt'); }))).toBe(false);
    expect(c.text()).toContain('Drive: fehlgeschlagen');
    expect(existsSync(join(dir, dateiName('2026-10-27')))).toBe(true);
  });

  test('leerer Dienst: nichts geschrieben, rclone nie gerufen', async () => {
    const leer = await baueMitCli();
    drive.length = 0;
    expect(await sicherung(leer.a, abh(tag1))).toBe(true);
    expect(drive).toEqual([]);
    expect(existsSync(join(leer.dateien, 'Sicherung', dateiName('2026-10-26')))).toBe(false);
    leer.ende();
  });
});

describe('heimherz wiederherstellen', () => {
  const datei = () => join(dir, dateiName('2026-10-27'));
  const rohEintraege = async (a: { dienstUrl: string; daten: string; creds: any }, k: Uint8Array) => {
    const token = (await fakeCreds.entschluessele('heimherz-token', join(a.daten, 'token.cred'))).trim();
    return (await ladeTresor({ url: a.dienstUrl, token }, k)).tresor.eintraege;
  };

  test('neuer PC ohne Schlüssel: Code öffnet die Sicherung, Tresor ist derselbe, K landet nur in der Ablage', async () => {
    const quelle = (await ladeTresor(v, key)).tresor.eintraege;
    const t = baue();
    const zeilen: string[] = [];
    const neu: Abh = { daten: t.daten, fotos: t.fotos, dateien: t.dateien, dienstUrl: t.url, creds: fakeCreds, ausgabe: z => zeilen.push(z) };
    await wiederherstellen(neu, datei(), async () => fxW.code.toLowerCase());
    expect(await ladeSchluessel(neu.daten, fakeCreds)).toEqual(key);
    expect(await rohEintraege(neu, key)).toEqual([...quelle].sort((x, y) => (x.id < y.id ? -1 : 1)));
    expect(zeilen.join('\n')).not.toMatch(/KOEDER|AQIDBAUG/);
    for (const g of [fxW.code, fxW.code.replaceAll('-', ''), ...muster(key)]) expect(zeilen.join('\n')).not.toContain(g);
    t.ende();
  });

  test('falscher Code: Meldung, kein Schlüssel gespeichert, nichts geschrieben', async () => {
    const t = baue();
    const neu: Abh = { daten: t.daten, fotos: t.fotos, dateien: t.dateien, dienstUrl: t.url, creds: fakeCreds, ausgabe: () => {} };
    await expect(wiederherstellen(neu, datei(), async () => 'AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA')).rejects.toThrow(Meldung);
    await expect(wiederherstellen(neu, datei(), async () => 'quatsch')).rejects.toThrow(Meldung);
    expect(existsSync(join(t.daten, 'schluessel.cred'))).toBe(false);
    expect((await t.f('/v1/tresor')).status).toBe(404);
    t.ende();
  });

  test('Sicherung ohne Blatt auf PC ohne Schlüssel: klare Meldung', async () => {
    const t = baue();
    const neu: Abh = { daten: t.daten, fotos: t.fotos, dateien: t.dateien, dienstUrl: t.url, creds: fakeCreds, ausgabe: () => {} };
    await expect(wiederherstellen(neu, join(dir, dateiName('2026-10-26')), async () => fxW.code)).rejects.toThrow('kein Wiederherstellungsblatt');
    t.ende();
  });

  test('derselbe PC mit K: Zusammenführen, neuere Einträge bleiben, gelöschte bleiben gelöscht', async () => {
    await aendereTresor(v, key, t => ({ ...t, eintraege: t.eintraege.map(e => e.id === 'a1' ? { ...e, passwort: 'KOEDER-NEU-9999', geaendert: new Date(Date.now() + 60_000).toISOString() } : e) }));
    await aendereTresor(v, key, t => ({ ...t, eintraege: [...t.eintraege, eintrag('a5', 'Fünf', 'KOEDER-NEU-5555', new Date(Date.now() + 60_000).toISOString())] }));
    await wiederherstellen(c.a, datei(), async () => { throw new Error('Code darf nicht gefragt werden'); });
    const e = (await ladeTresor(v, key)).tresor.eintraege;
    expect(e.find(x => x.id === 'a1')!.passwort).toBe('KOEDER-NEU-9999');   // neuer als die Sicherung
    expect(e.map(x => x.id).sort()).toEqual(['a1', 'a2', 'a3', 'a4', 'a5']);   // a5 gab es in der Sicherung nicht
  });

  test('Schlüssel passt nicht zur Sicherung: Abbruch, K unverändert, Tresor unberührt', async () => {
    const t = baue();
    const fremd: Abh = { daten: t.daten, fotos: t.fotos, dateien: t.dateien, dienstUrl: t.url, creds: fakeCreds, ausgabe: () => {} };
    await einrichtenBefehl(fremd);   // eigener Zufallsschlüssel
    const k0 = readFileSync(join(t.daten, 'schluessel.cred'), 'utf8');
    await expect(wiederherstellen(fremd, datei(), async () => fxW.code)).rejects.toThrow('passt nicht');
    expect(readFileSync(join(t.daten, 'schluessel.cred'), 'utf8')).toBe(k0);
    expect((await t.f('/v1/tresor')).status).toBe(404);
    t.ende();
  });

  test('keine Sicherungsdatei: Meldung, nichts passiert', async () => {
    writeFileSync(join(c.wurzel, 'quatsch.heimsicherung'), '{"a":1}');
    await expect(wiederherstellen(c.a, join(c.wurzel, 'quatsch.heimsicherung'), async () => '')).rejects.toThrow('nichts geändert');
  });
});
