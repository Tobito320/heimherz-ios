import { afterAll, expect, test } from 'bun:test';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import fx from '../fixtures/bitwarden/export-beispiel.json';
import fxTresor from '../fixtures/tresor/umschlag-1.json';
import { b64, oeffne, schluessel, verschliesse } from '../lib/umschlag';
import type { Tresor } from '../lib/zusammenfuehren';
import { vonBitwarden } from './bitwarden';
import { Meldung, einrichtenBefehl, exportBitwarden, geraetWeg, importBitwarden, liste, status } from './befehle';
import { aendereTresor, ladeTresor } from './tresorclient';
import { einrichten, ladeSchluessel, ladeToken } from './schluessel';
import { hashe, leseGeraete, schreibeGeraete } from '../server/geraete';
import { baueMitCli, fakeCreds } from './testhilfe';

const c = await baueMitCli();
afterAll(c.ende);
const PASSWOERTER = fx.items.map(i => (i as any).login?.password).filter(Boolean) as string[];
const holeBw = async () => JSON.stringify(fx);
const rev = async () => ((await (await c.f('/v1/status')).json()) as any).rev;
const key = b64(fxTresor.schluessel);
const v = { url: c.url, token: c.token };

test('einrichten überschreibt nie einen vorhandenen Schlüssel', async () => {
  const vorher = readFileSync(join(c.daten, 'schluessel.cred'), 'utf8');
  await einrichtenBefehl(c.a);
  expect(readFileSync(join(c.daten, 'schluessel.cred'), 'utf8')).toBe(vorher);
  expect(c.text()).toContain('Schlüssel war schon da');
  expect(c.text()).toContain('Gerät pc war schon da');
  c.leere();
});

test('einrichten auf leerem Ordner: Schlüssel 32 Byte, Token, Gerät pc, Ausgabe ohne Geheimnisse', async () => {
  const d = mkdtempSync(join(tmpdir(), 'heimherz-einr-'));
  try {
    const o = { daten: join(d, 'daten'), fotos: join(d, 'f'), dateien: join(d, 'd'), creds: fakeCreds };
    const m = await einrichten(o);
    expect(m).toEqual(['Schlüssel angelegt', 'Gerät pc angelegt']);
    expect((await ladeSchluessel(o.daten, o.creds)).length).toBe(32);
    const token = await ladeToken(o.daten, o.creds);
    expect(leseGeraete(o.daten)).toMatchObject([{ id: 'pc', name: 'pc', hash: hashe(token) }]);
    expect(statSync(o.daten).mode & 0o777).toBe(0o700);
    expect(existsSync(o.fotos) && existsSync(o.dateien)).toBe(true);
    // zweiter Lauf ändert nichts
    const k1 = readFileSync(join(o.daten, 'schluessel.cred'), 'utf8');
    expect(await einrichten(o)).toEqual(['Schlüssel war schon da, unverändert', 'Gerät pc war schon da']);
    expect(readFileSync(join(o.daten, 'schluessel.cred'), 'utf8')).toBe(k1);
  } finally { rmSync(d, { recursive: true, force: true }); }
});

test('Import: Zahlen, Server hat nur Chiffretext, Test-Schlüssel öffnet ihn', async () => {
  await importBitwarden(c.a, holeBw);
  expect(c.leere()).toEqual(['3 Logins, 1 Notizen, 3 übersprungen']);
  expect(await rev()).toBe(1);
  const roh = readFileSync(join(c.daten, 'tresor/aktuell.json'), 'utf8');
  for (const p of PASSWOERTER) expect(roh).not.toContain(p);
  const { tresor } = await ladeTresor(v, key);
  expect(tresor.eintraege.map(e => e.name).sort()).toEqual(['Beispiel Shop', 'Ohne Adresse', 'Passkey-Seite', 'WLAN-Zettel']);
  expect(tresor.eintraege.find(e => e.name === 'Passkey-Seite')!.bitwardenFido2).toBeDefined();
});

test('erneuter Import ohne Dubletten und ohne neue Fassung', async () => {
  await importBitwarden(c.a, holeBw);
  c.leere();
  expect((await ladeTresor(v, key)).tresor.eintraege).toHaveLength(4);
  expect(await rev()).toBe(1);
});

test('am Handy geänderter Eintrag (neuer) überlebt einen erneuten Import; geänderter Bitwarden-Eintrag kommt dazu', async () => {
  await aendereTresor(v, key, t => ({ ...t, eintraege: t.eintraege.map(e => (e.name === 'Beispiel Shop' ? { ...e, passwort: 'Handy-Neu-444', geaendert: '2026-10-20T00:00:00.000Z' } : e)) }));
  const geaendert = { ...fx, items: fx.items.map(i => (i.name === 'Ohne Adresse' ? { ...i, name: 'Jetzt mit Name', revisionDate: '2026-10-21T00:00:00.000Z' } : i)) };
  await importBitwarden(c.a, async () => JSON.stringify(geaendert));
  const { tresor } = await ladeTresor(v, key);
  expect(tresor.eintraege).toHaveLength(4);
  expect(tresor.eintraege.find(e => e.id === 'b0000000-0000-4000-8000-000000000001')!.passwort).toBe('Handy-Neu-444');
  expect(tresor.eintraege.find(e => e.id === 'b0000000-0000-4000-8000-000000000003')!.name).toBe('Jetzt mit Name');
});

test('liste: Kopf, Zeilen, Suche; nie Passwort, TOTP-Geheimnis oder Notiztext', async () => {
  c.leere();
  await liste(c.a);
  const alles = c.text();
  expect(c.zeilen[0]).toBe('id\tname\tbenutzer\thosts\ttotp');
  expect(c.zeilen).toHaveLength(5);
  expect(alles).toContain('shop.example.org,www.shop.example.org');
  expect(c.zeilen.find(z => z.includes('Beispiel Shop'))!.endsWith('\tja')).toBe(true);
  expect(c.zeilen.find(z => z.includes('Passkey-Seite'))!.endsWith('\tnein')).toBe(true);
  for (const geheim of [...PASSWOERTER, 'Handy-Neu-444', 'GEZDGNBVGY3TQOJQ', 'nicht-echt-123', 'Erfundene Notiz', 'otpauth']) expect(alles).not.toContain(geheim);
  c.leere();
  await liste(c.a, 'PASSKEY');
  expect(c.zeilen).toHaveLength(2);
  c.leere();
  await liste(c.a, 'max');   // Benutzer
  expect(c.zeilen).toHaveLength(2);
  c.leere();
  await liste(c.a, 'nix-passt');
  expect(c.zeilen).toHaveLength(1);
});

test('Export: Bitwarden-JSON 0600, gleiche Logins wie der Import, existierende Datei bleibt unberührt', async () => {
  const ziel = join(c.wurzel, 'export.json');
  c.leere();
  await exportBitwarden(c.a, ziel);
  expect(statSync(ziel).mode & 0o777).toBe(0o600);
  expect(c.text()).not.toContain(PASSWOERTER[0]);
  const aus = JSON.parse(readFileSync(ziel, 'utf8'));
  expect(aus.encrypted).toBe(false);
  const zurueck = vonBitwarden(aus);
  const { tresor } = await ladeTresor(v, key);
  expect(zurueck.eintraege).toEqual(tresor.eintraege);
  expect(aus.items.find((i: any) => i.name === 'Beispiel Shop').login.password).toBe('Handy-Neu-444');
  await expect(exportBitwarden(c.a, ziel)).rejects.toThrow(Meldung);
  expect(JSON.parse(readFileSync(ziel, 'utf8'))).toEqual(aus);
});

test('Bitwarden gesperrt oder Müll: nichts wird verändert, keine Inhaltsfetzen in der Meldung', async () => {
  const vor = await rev();
  await expect(importBitwarden(c.a, async () => { throw new Meldung('Bitwarden gesperrt: claude-bw entsperre'); })).rejects.toThrow('Bitwarden gesperrt');
  const err = await importBitwarden(c.a, async () => 'Erfunden-Passwort-111! kein json').catch(e => e);
  expect(err).toBeInstanceOf(Meldung);
  expect(String(err.message)).not.toContain('Erfunden');
  expect(await rev()).toBe(vor);
});

const eintrag = (id: string, name: string) => ({ id, art: 'notiz' as const, name, benutzer: '', passwort: '', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-22T00:00:00.000Z', geloescht: false });

// Ein zweites Gerät schreibt, während das CLI gerade ändert.
async function dazwischen(id: string) {
  const { tresor, rev: r } = await ladeTresor(v, key);
  const u = await verschliesse({ ...tresor, eintraege: [...tresor.eintraege, eintrag(id, 'Dazwischen ' + id)] }, await schluessel(key));
  expect((await c.f('/v1/tresor', { method: 'PUT', headers: { 'if-match': String(r) }, body: JSON.stringify(u) })).status).toBe(200);
}

test('aendereTresor: bei 409 neu holen und erneut anwenden, nichts geht verloren', async () => {
  let aufrufe = 0;
  await aendereTresor(v, key, async t => {
    if (++aufrufe === 1) await dazwischen('D-1');
    return { ...t, eintraege: [...t.eintraege, eintrag('M-1', 'Meins')] };
  });
  expect(aufrufe).toBe(2);
  const namen = (await ladeTresor(v, key)).tresor.eintraege.map(e => e.id);
  expect(namen).toContain('D-1');
  expect(namen).toContain('M-1');
});

test('aendereTresor: nach 3 Konflikten klare Meldung, kein Absturz', async () => {
  let aufrufe = 0;
  const e = await aendereTresor(v, key, async t => {
    await dazwischen('K-' + ++aufrufe);
    return { ...t, eintraege: [...t.eintraege, eintrag('M-2', 'Nie')] };
  }).catch(x => x);
  expect(aufrufe).toBe(3);
  expect(e).toBeInstanceOf(Error);
  expect(String(e.message)).toContain('zu oft');
  expect((await ladeTresor(v, key)).tresor.eintraege.some(x => x.id === 'M-2')).toBe(false);
});

test('status: läuft, rev, Geräte; keine Token oder Hashes', async () => {
  c.leere();
  await status(c.a);
  const t = c.text();
  expect(t).toContain('Dienst: läuft');
  expect(t).toContain('Tresor rev');
  expect(t).toContain('Fotos: 0 gesamt, 0 heute');
  expect(t).toContain('  pc\tpc\t');
  expect(t).not.toContain(c.token);
  expect(t).not.toMatch(/[0-9a-f]{64}/);
});

test('status bei ausgeschaltetem Dienst: Meldung statt Absturz', async () => {
  c.leere();
  await status({ ...c.a, dienstUrl: 'http://127.0.0.1:9' });
  expect(c.text()).toContain('Dienst: aus');
});

test('geraet weg: Token gilt nicht mehr; pc und unbekannte ids werden abgelehnt', async () => {
  schreibeGeraete(c.daten, [...leseGeraete(c.daten), { id: 'abcd1234', name: 'iPhone', hash: hashe('handy-token'), angelegt: 'a', zuletzt: null }]);
  expect((await c.ohne('/v1/status', { headers: { authorization: 'Bearer handy-token' } })).status).toBe(200);
  geraetWeg(c.a, 'abcd1234');
  expect((await c.ohne('/v1/status', { headers: { authorization: 'Bearer handy-token' } })).status).toBe(401);
  expect(() => geraetWeg(c.a, 'abcd1234')).toThrow(Meldung);
  expect(() => geraetWeg(c.a, 'pc')).toThrow('CLI selbst');
  expect((await c.f('/v1/status')).status).toBe(200);
});

test('Test-Schlüssel stimmt mit der Fixture überein (Umschlag aus dem Server ist lesbar)', async () => {
  const u = await (await c.f('/v1/tresor')).json() as any;
  expect(((await oeffne<Tresor>(u, await schluessel(key))).format)).toBe(1);
});
