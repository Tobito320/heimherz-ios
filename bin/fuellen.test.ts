import { afterAll, expect, test } from 'bun:test';
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Eintrag } from '../lib/zusammenfuehren';
import { eigenerTab, fuelleFeld, FuellFehler, handyHinweis, leseSchluessel, mitTotp, protokoll, waehle, wertVon } from './fuellen';
import { aendereTresor, ladeTresor } from './tresorclient';
import { totpSetzen } from './befehle';
import { baueMitCli, TESTSCHLUESSEL_B64URL } from './testhilfe';

const ordner = mkdtempSync(join(tmpdir(), 'heimherz-fuellen-'));
afterAll(() => rmSync(ordner, { recursive: true, force: true }));
const e = (x: Partial<Eintrag>): Eintrag => ({ id: 'id-' + Math.random().toString(36).slice(2), art: 'login', name: 'x', benutzer: 'tobi@beispiel.de', passwort: 'erfunden-1', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00Z', geloescht: false, ...x });
const TOTP = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

test('Eintragswahl: Seite, Unterdomain, fremde Seite, gelöscht', () => {
  const sso = e({ id: 'aaa', urls: ['https://sso.beispiel-amt.de/login'] });
  const l = [sso, e({ id: 'bbb', urls: ['https://beispiel-amt.de.boese.example/'] }), e({ id: 'ccc', urls: ['https://web.beispiel-amt.de/'], geloescht: true })];
  expect(waehle(l, 'https://web.beispiel-amt.de/post', 'passwort').id).toBe('aaa');
  expect(() => waehle(l, 'https://andere.example/', 'passwort')).toThrow(FuellFehler);
  expect(waehle(l, 'https://boese.example/', 'passwort').id).toBe('bbb');   // Eintrag gehört zu boese.example, nicht zum Amt
  expect(() => waehle([e({ art: 'notiz', urls: ['https://beispiel.de'] })], 'https://beispiel.de', 'benutzer')).toThrow('Kein');
});

test('Doppelte: gleiche Person nimmt den mit TOTP, dann den neuesten; verschiedene Personen brauchen --konto', () => {
  const ohne = e({ id: 'ohne', urls: ['https://sso.amt.de'], geaendert: '2026-10-20T00:00:00Z' });
  const mit = e({ id: 'mit', urls: ['https://amt.de'], totp: TOTP, geaendert: '2026-09-01T00:00:00Z' });
  expect(waehle([ohne, mit], 'https://sso.amt.de/', 'passwort').id).toBe('mit');
  expect(waehle([ohne, mit], 'https://sso.amt.de/', 'code').id).toBe('mit');
  const alt = e({ id: 'alt', urls: ['https://apple.com'], geaendert: '2026-01-01T00:00:00Z' }), neu = e({ id: 'neu', urls: ['https://apple.com'], geaendert: '2026-10-01T00:00:00Z' });
  expect(waehle([alt, neu], 'https://idmsa.apple.com/', 'passwort').id).toBe('neu');
  const fremd = e({ id: 'fremd', benutzer: 'kausar@beispiel.de', urls: ['https://amt.de'] });
  expect(() => waehle([ohne, fremd], 'https://amt.de/', 'passwort')).toThrow('--konto');
  expect(waehle([ohne, fremd], 'https://amt.de/', 'passwort', 'kausar@beispiel.de').id).toBe('fremd');
  expect(waehle([ohne, fremd], 'https://amt.de/', 'passwort', 'fre').id).toBe('fremd');
  expect(() => waehle([ohne], 'https://amt.de/', 'code')).toThrow('TOTP');
});

test('Code wartet, wenn er gleich abläuft', async () => {
  let gewartet = 0, jetzt = 29_000;
  const c = await wertVon(e({ totp: TOTP }), 'code', () => jetzt, async ms => { gewartet = ms; jetzt += ms; });
  expect(gewartet).toBeGreaterThan(0);
  expect(c).toMatch(/^\d{6}$/);
});

test('Nur eigene https-Tabs', () => {
  const tabs = 'AB12  w1  Titel  https://sso.amt.de/login\nCD34  w1  Lokal  http://127.0.0.1/x';
  expect(eigenerTab(tabs, 'sso.amt').id).toBe('AB12');
  expect(() => eigenerTab(tabs, 'CD34')).toThrow('https');
  expect(() => eigenerTab(tabs, 'fremd')).toThrow('nicht in deinen Fenstern');
});

test('Protokoll und Hinweis enthalten nie Werte', () => {
  protokoll(ordner, { host: 'sso.amt.de', id: 'abcdef123456', was: 'passwort', stufe: 3, modell: 'opus', ok: true, grund: 'Stufe 3, opus' });
  const log = readFileSync(join(ordner, 'fuell.log'), 'utf8');
  expect(log).toContain('sso.amt.de\tabcdef12\tpasswort\tstufe 3\topus\terlaubt');
  expect(statSync(join(ordner, 'fuell.log')).mode & 0o777).toBe(0o600);
  handyHinweis(ordner, 'Sparkasse: Login durch Agent', 'Sitzung x füllt www.spkvr.de');
  const h = readdirSync(join(ordner, 'zentrale-hinweis')).filter(f => f.endsWith('.json'));
  expect(h.length).toBe(1);
  expect(JSON.parse(readFileSync(join(ordner, 'zentrale-hinweis', h[0]), 'utf8')).titel).toBe('Sparkasse: Login durch Agent');
});

test('mitTotp: prüft Base32, setzt geaendert, alter Schlüssel in totpVerlauf', () => {
  const jetzt = new Date('2026-10-25T12:00:00Z');
  expect(() => mitTotp(e({}), 'kein-schluessel!', jetzt)).toThrow('Base32');
  expect(() => mitTotp(e({}), 'ABCDEF', jetzt)).toThrow('Base32');
  const n = mitTotp(e({}), 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq', jetzt);
  expect(n.totp).toBe(TOTP);
  expect(n.geaendert).toBe(jetzt.toISOString());
  expect(n.totpVerlauf).toBeUndefined();
  const alt = e({ totp: 'JBSWY3DPEHPK3PXPJBSWY3DP' });
  const m = mitTotp(alt, TOTP, jetzt);
  expect(m.totpVerlauf).toEqual([{ totp: 'JBSWY3DPEHPK3PXPJBSWY3DP', bis: jetzt.toISOString() }]);
  expect(mitTotp(m, TOTP, jetzt)).toBe(m);   // gleicher Schlüssel: nichts ändern
  expect(mitTotp(e({}), `otpauth://totp/x?secret=${TOTP}&digits=8`, jetzt).totp).toContain('digits=8');
});

test('totpSetzen schreibt in den Tresor und gibt den Schlüssel nie aus', async () => {
  const c = await baueMitCli();
  try {
    const k = Buffer.from(TESTSCHLUESSEL_B64URL, 'base64url'), v = { url: c.url, token: c.token };
    await aendereTresor(v, k, t => ({ ...t, eintraege: [e({ id: 'gh', urls: ['https://github.com'] })] }));
    expect(await totpSetzen(c.a, 'gh', TOTP)).toBe(true);
    expect(await totpSetzen(c.a, 'gh', TOTP)).toBe(false);
    expect((await ladeTresor(v, k)).tresor.eintraege[0].totp).toBe(TOTP);
    await expect(totpSetzen(c.a, 'fehlt', TOTP)).rejects.toThrow('nicht mehr da');
    expect(c.text()).not.toContain(TOTP);
  } finally { c.ende(); }
});

// Echter Chrome ohne Profil und ohne Netz: Feld füllen, doppelt vermeiden, Enter.
const chrome = ['google-chrome-stable', 'chromium'].map(b => Bun.which(b)).find(Boolean);
test.skipIf(!chrome)('CDP füllt das Feld und meldet nur die Länge', async () => {
  const port = 9556, profil = join(ordner, 'chrome');
  const seite = 'data:text/html,' + encodeURIComponent('<form onsubmit="document.title=\'gesendet\';return false"><input id=u><input id=p type=password><button>Los</button></form>');
  const p = Bun.spawn([chrome!, '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profil}`, '--no-first-run', seite], { stdout: 'ignore', stderr: 'ignore' });
  try {
    let tab: any;
    for (let i = 0; i < 50 && !tab; i++) { try { tab = ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).find(t => t.type === 'page'); } catch { /* startet noch */ } if (!tab) await Bun.sleep(100); }
    expect(tab).toBeTruthy();
    expect(await fuelleFeld({ port, tabId: tab.id, css: '#p' }, 'erfunden-geheim')).toEqual({ laenge: 15, schon: false });
    expect(await fuelleFeld({ port, tabId: tab.id, css: '#p', enter: true }, 'erfunden-geheim')).toEqual({ laenge: 15, schon: true });
    await expect(fuelleFeld({ port, tabId: tab.id, css: '#fehlt' }, 'x')).rejects.toThrow('Feld nicht gefunden');
    const ws = new WebSocket(tab.webSocketDebuggerUrl); await new Promise(r => (ws.onopen = r));
    const titel = await new Promise<string>(r => { ws.onmessage = m => r(JSON.parse(String(m.data)).result.result.value); ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: 'document.title', returnByValue: true } })); });
    ws.close();
    expect(titel).toBe('gesendet');
  } finally { p.kill(); await p.exited; }
}, 20000);

test.skipIf(!chrome)('Schlüssel von der Seite: eindeutiger Text, --feld, mehrdeutig, keiner', async () => {
  const port = 9557, profil = join(ordner, 'chrome2');
  const html = (b: string) => 'data:text/html,' + encodeURIComponent(`<p>Sicherheitseinstellungen</p>${b}`);
  const p = Bun.spawn([chrome!, '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profil}`, '--no-first-run', html('<p>Schlüssel:</p><code>gezd gnbv gy3t qojq gezd gnbv gy3t qojq</code><input id=k value="JBSWY3DPEHPK3PXPJBSWY3DP">')], { stdout: 'ignore', stderr: 'ignore' });
  try {
    let tab: any;
    for (let i = 0; i < 50 && !tab; i++) { try { tab = ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).find(t => t.type === 'page' && t.url.startsWith('data:')); } catch { /* startet noch */ } if (!tab) await Bun.sleep(100); }
    await expect(leseSchluessel({ port, tabId: tab.id })).rejects.toThrow('2 mögliche');
    expect(await leseSchluessel({ port, tabId: tab.id, feld: '#k' })).toBe('JBSWY3DPEHPK3PXPJBSWY3DP');
    const geh = async (u: string) => { await fetch(`http://127.0.0.1:${port}/json/new?${u}`, { method: 'PUT' }); };
    await geh(html('<span>gezd gnbv  gy3t qojq<br>gezd gnbv gy3t qojq</span>'));
    await Bun.sleep(500);
    const tabs = ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).filter(t => t.type === 'page' && t.url.startsWith('data:'));
    const zwei = tabs.find(t => t.id !== tab.id);
    expect((await leseSchluessel({ port, tabId: zwei.id })).replace(/ /g, '').toUpperCase()).toBe(TOTP);
    await geh(html('<p>nichts</p>')); await Bun.sleep(500);
    const drei = ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).find(t => t.type === 'page' && t.url.startsWith('data:') && ![tab.id, zwei.id].includes(t.id));
    await expect(leseSchluessel({ port, tabId: drei.id })).rejects.toThrow('Kein Einrichtungsschlüssel');
  } finally { p.kill(); await p.exited; }
}, 20000);

