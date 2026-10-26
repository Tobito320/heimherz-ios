import { afterAll, expect, test } from 'bun:test';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Eintrag } from '../lib/zusammenfuehren';
import { passwortSetzen } from './befehle';
import { FuellFehler, type Was } from './fuellen';
import { leseGedaechtnis, liesFeld, loginAblauf, LOGIN_EXIT, merkeSeite, mitPasswort } from './login';
import { aendereTresor, ladeTresor } from './tresorclient';
import { baueMitCli, TESTSCHLUESSEL_B64URL } from './testhilfe';

const ordner = mkdtempSync(join(tmpdir(), 'heimherz-login-'));
afterAll(() => rmSync(ordner, { recursive: true, force: true }));
const e = (x: Partial<Eintrag>): Eintrag => ({ id: 'id-' + Math.random().toString(36).slice(2), art: 'login', name: 'x', benutzer: 'tobi@beispiel.de', passwort: 'erfunden-1', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00Z', geloescht: false, ...x });
const JETZT = new Date('2026-10-26T12:00:00Z');

test('mitPasswort: neues Passwort, altes in passwortVerlauf (höchstens 5), gleiches ändert nichts', () => {
  expect(() => mitPasswort(e({}), '', JETZT)).toThrow(FuellFehler);
  const a = e({ passwort: 'alt-1' }), n = mitPasswort(a, 'neu-2', JETZT);
  expect(n.passwort).toBe('neu-2');
  expect(n.geaendert).toBe(JETZT.toISOString());
  expect(n.passwortVerlauf).toEqual([{ passwort: 'alt-1', bis: JETZT.toISOString() }]);
  expect(mitPasswort(n, 'neu-2', JETZT)).toBe(n);
  let x = n; for (let i = 0; i < 8; i++) x = mitPasswort(x, 'p' + i, JETZT);
  expect((x.passwortVerlauf as unknown[]).length).toBe(5);
  expect(mitPasswort(e({ passwort: '' }), 'erstes', JETZT).passwortVerlauf).toBeUndefined();
});

test('passwortSetzen schreibt in den Tresor und gibt das Passwort nie aus', async () => {
  const c = await baueMitCli();
  try {
    const k = Buffer.from(TESTSCHLUESSEL_B64URL, 'base64url'), v = { url: c.url, token: c.token };
    await aendereTresor(v, k, t => ({ ...t, eintraege: [e({ id: 'gh', passwort: 'alt-geheim', urls: ['https://github.com'] })] }));
    expect(await passwortSetzen(c.a, 'gh', 'neu-geheim')).toBe(true);
    expect(await passwortSetzen(c.a, 'gh', 'neu-geheim')).toBe(false);
    const it = (await ladeTresor(v, k)).tresor.eintraege[0];
    expect(it.passwort).toBe('neu-geheim');
    expect((it.passwortVerlauf as any[])[0].passwort).toBe('alt-geheim');
    await expect(passwortSetzen(c.a, 'fehlt', 'x')).rejects.toThrow('nicht mehr da');
    expect(c.text()).not.toContain('geheim');
  } finally { c.ende(); }
});

test('Gedächtnis: nur nach Erfolg, nur Selektoren, Datei 0600', () => {
  const dir = join(ordner, 'gedaechtnis');
  merkeSeite(dir, 'a.example', { ergebnis: 'falsches-passwort', hinweis: '', benutzt: { passwort: '#p' } }, JETZT);
  expect(leseGedaechtnis(dir)).toEqual({});
  merkeSeite(dir, 'a.example', { ergebnis: 'eingeloggt', hinweis: '', benutzt: { benutzer: '#u', passwort: '#p', absenden: 'body > form > button' }, erfolgPfad: 'https://a.example/start' }, JETZT);
  expect(leseGedaechtnis(dir)['a.example']).toEqual({ benutzer: '#u', passwort: '#p', erfolgPfad: 'https://a.example/start', zuletzt: JETZT.toISOString() });
  expect(statSync(join(dir, 'login-gedaechtnis.json')).mode & 0o777).toBe(0o600);
  expect(leseGedaechtnis(join(ordner, 'nichts'))).toEqual({});
});

test('Exit-Codes sind verschieden und 0 nur für eingeloggt', () => {
  const v = Object.values(LOGIN_EXIT);
  expect(new Set(v).size).toBe(v.length);
  expect(LOGIN_EXIT.eingeloggt).toBe(0);
  expect(v.filter(x => x === 0).length).toBe(1);
});

// Echter Chrome ohne Profil und ohne Netz.
const chrome = ['google-chrome-stable', 'chromium'].map(b => Bun.which(b)).find(Boolean);
const SEITEN = {
  zweistufig: `<div id=w><form id=f1><label for=u>E-Mail</label><input id=u type=email autocomplete=username><button type=submit>Weiter</button></form></div><script>
    f1.onsubmit=e=>{e.preventDefault();w.innerHTML='<form id=f2><input id=pw type=password autocomplete=current-password><button type=submit>Anmelden</button></form>';
    f2.onsubmit=e=>{e.preventDefault();if(pw.value==='richtig'){w.innerHTML='<h1>Willkommen</h1>'}else{w.insertAdjacentHTML('beforeend','<p class=error>Passwort ist falsch</p>')}}}</script>`,
  zweifa: `<div id=w><form id=f><input name=konto><input name=kennwort type=password><button>Anmelden</button></form></div><script>
    f.onsubmit=e=>{e.preventDefault();w.innerHTML='<form id=g><input name=otp autocomplete=one-time-code><button>Bestätigen</button></form>';
    g.onsubmit=e=>{e.preventDefault();w.innerHTML=g.otp.value==='123456'?'<h1>Willkommen</h1>':'<input name=otp>'}}</script>`,
  enter: `<div id=w><input id=u autocomplete=username><input id=pw type=password></div><script>pw.onkeydown=e=>{if(e.key==='Enter')w.innerHTML='<h1>Willkommen</h1>'}</script>`,
  captcha: `<form><input id=u><input id=pw type=password><div class=g-recaptcha style="width:80px;height:40px"></div><button>Los</button></form>`,
  spaet: `<div id=w><form id=f1><input id=u type=email autocomplete=username><button type=submit>Weiter</button></form></div><script>
    f1.onsubmit=e=>{e.preventDefault();w.innerHTML='<p>Einen Moment ...</p>';setTimeout(()=>{w.innerHTML='<form id=f2><input id=pw type=password><button type=submit>Anmelden</button></form>';
    f2.onsubmit=e=>{e.preventDefault();w.innerHTML=pw.value==='richtig'?'<h1>Willkommen</h1>':'<p class=error>falsch</p>'}},500)}</script>`,
  kauf: `<form><input id=u><input id=pw type=password><button>Jetzt kaufen</button></form>`,
  // sso.arbeitsagentur.de: vor "Anmelden" steht "Mit Passkey anmelden"; der falsche Knopf zeigt eine Fehlermeldung
  passkey: `<div id=w><input id=u autocomplete=username><input id=pw type=password><button type=button id=pk onclick="w.insertAdjacentHTML('beforeend','<p class=error>Passkey nicht verfügbar</p>')">Mit Passkey anmelden</button><button type=button id=ok>Anmelden</button></div><script>ok.onclick=()=>{w.innerHTML='<h1>Willkommen</h1>'}</script>`,
  // Mark-E: Erfolg ist da, das Passwortfeld verschwindet erst nach rund 1,2 s
  verzoegert: `<div id=w><input id=u autocomplete=username><input id=pw type=password><button id=b>Anmelden</button></div><script>b.onclick=()=>{setTimeout(()=>{w.innerHTML='<h1>Willkommen</h1>'},1200)}</script>`,
  // Die Seite meldet nach dem Absenden nichts und behält das Feld: bleibt Exit 8
  stumm: `<div id=w><input id=u autocomplete=username><input id=pw type=password><button id=b>Anmelden</button></div><script>b.onclick=()=>{b.textContent='Anmelden ...'}</script>`,
  wartet: `<meta charset=utf-8><h1>Bestätige die Anmeldung in der App auf deinem Handy</h1>`,
  drin: `<h1>Willkommen</h1><input id=suche placeholder=Suche>`,
  feld: `<input id=neu type=password value="Handy-Passwort-9"><input id=leer type=password>`,
};
const WERT: Record<Was, string> = { benutzer: 'tobi@beispiel.de', passwort: 'richtig', code: '123456' };

test.skipIf(!chrome)('Login gegen Wegwerf-Chrome: zweistufig, falsches Passwort, 2FA, Enter, Captcha, schon drin, Gedächtnis, merke', async () => {
  const port = 9558, profil = join(ordner, 'chrome');
  const p = Bun.spawn([chrome!, '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profil}`, '--no-first-run', '--disable-extensions', 'about:blank']   // --disable-extensions: die Richtlinie /etc/opt/chrome/policies installiert sonst eine Erweiterung, die im frischen Profil Kern und Test ausbremst
  , { stdout: 'ignore', stderr: 'ignore' });
  const alle = async () => ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).filter(t => t.type === 'page');
  const oeffne = async (html: string) => {
    const vor = new Set((await alle()).map(t => t.id));
    await fetch(`http://127.0.0.1:${port}/json/new?${'data:text/html,' + encodeURIComponent(html)}`, { method: 'PUT' });
    for (let i = 0; i < 50; i++) { const t = (await alle()).find(x => !vor.has(x.id) && x.url.startsWith('data:')); if (t) { await Bun.sleep(150); return t.id as string; } await Bun.sleep(100); }
    throw new Error('Tab fehlt');
  };
  const holte: Was[] = [];
  const lauf = async (html: string, mitCode = false, wert = WERT, bekannt?: any) => {
    const tabId = await oeffne(html);
    try { return await loginAblauf({ port, tabId, mitCode, bekannt, warteMs: 1500, beruhigtMs: 600, wert: async w => { holte.push(w); return wert[w]; } }); }
    finally { await fetch(`http://127.0.0.1:${port}/json/close/${tabId}`); }   // sonst bremsen die offenen Tabs den Wegwerf-Chrome
  };
  try {
    for (let i = 0; i < 50; i++) { try { await alle(); break; } catch { await Bun.sleep(100); } }

    const ok = await lauf(SEITEN.zweistufig);
    expect(ok.ergebnis).toBe('eingeloggt');
    expect(ok.benutzt).toMatchObject({ benutzer: '#u', passwort: '#pw' });
    expect(ok.benutzt.absenden).toBeTruthy();

    const falsch = await lauf(SEITEN.zweistufig, false, { ...WERT, passwort: 'verkehrt' });
    expect(falsch.ergebnis).toBe('falsches-passwort');
    expect(falsch.passwortFeld).toBe('#pw');

    expect((await lauf(SEITEN.zweifa)).ergebnis).toBe('2fa');
    holte.length = 0;
    expect((await lauf(SEITEN.zweifa, true)).ergebnis).toBe('eingeloggt');
    expect(holte).toEqual(['benutzer', 'passwort', 'code']);
    expect((await lauf(SEITEN.zweifa, true, { ...WERT, code: '000000' })).ergebnis).toBe('unbekannt');   // Code abgelehnt

    expect((await lauf(SEITEN.enter)).ergebnis).toBe('eingeloggt');
    expect((await lauf(SEITEN.passkey)).ergebnis).toBe('eingeloggt');   // "Anmelden", nicht "Mit Passkey anmelden"
    expect((await lauf(SEITEN.verzoegert)).ergebnis).toBe('eingeloggt');   // nicht Exit 8, obwohl das Feld noch kurz da ist
    expect((await lauf(SEITEN.stumm)).ergebnis).toBe('falsches-passwort');
    expect((await lauf(SEITEN.captcha)).ergebnis).toBe('captcha');
    holte.length = 0;
    const drin = await lauf(SEITEN.drin);
    expect(drin.ergebnis).toBe('unbekannt');                         // keine Felder und nichts gefüllt: kann Laden sein, nicht raten
    expect(holte).toEqual([]);
    expect((await lauf(SEITEN.drin, false, WERT, { erfolgPfad: drin.url })).ergebnis).toBe('eingeloggt');   // bekannter Erfolgspfad
    expect((await lauf(SEITEN.wartet)).ergebnis).toBe('unbekannt');
    expect((await lauf(SEITEN.wartet)).hinweis).toContain('Bestätigung');
    // Schritt 2 kommt erst nach 500 ms: die leere Zwischenseite ist kein Erfolg
    holte.length = 0;
    expect((await lauf(SEITEN.spaet)).ergebnis).toBe('eingeloggt');
    expect(holte).toEqual(['benutzer', 'passwort']);
    expect((await lauf(SEITEN.spaet, false, { ...WERT, passwort: 'verkehrt' })).ergebnis).toBe('falsches-passwort');
    // Kauf-Knopf wird nie geklickt, und nichts wird vorher gefüllt
    holte.length = 0;
    const kauf = await lauf(SEITEN.kauf);
    expect(kauf.ergebnis).toBe('unbekannt'); expect(kauf.hinweis).toContain('Kaufen'); expect(holte).toEqual([]);
    // Eintrag ohne Benutzer: Fehler statt "falsches Passwort"
    await expect(lauf(SEITEN.zweistufig, false, { ...WERT, benutzer: '' })).rejects.toThrow('keinen Wert für benutzer');

    // veraltete gemerkte Selektoren fallen auf die Suche zurück; gültige werden benutzt
    expect((await lauf(SEITEN.zweistufig, false, WERT, { benutzer: '#gibtsnicht', passwort: '#auch-nicht' })).ergebnis).toBe('eingeloggt');
    expect((await lauf(SEITEN.zweistufig, false, WERT, ok.benutzt)).ergebnis).toBe('eingeloggt');

    // Gedächtnis enthält keine Werte
    merkeSeite(ordner, 'x.example', ok);
    const g = readFileSync(join(ordner, 'login-gedaechtnis.json'), 'utf8');
    expect(g).not.toContain('tobi@beispiel.de');
    expect(Object.keys(JSON.parse(g)['x.example']).sort()).toEqual(['benutzer', 'erfolgPfad', 'passwort', 'zuletzt']);   // absenden nur ohne 'body >'-Pfad

    // merke: Wert aus dem Feld lesen
    const feld = await oeffne(SEITEN.feld);
    expect(await liesFeld({ port, tabId: feld, css: '#neu' })).toBe('Handy-Passwort-9');
    await expect(liesFeld({ port, tabId: feld, css: '#leer' })).rejects.toThrow('leer');
    await expect(liesFeld({ port, tabId: feld, css: '#fehlt' })).rejects.toThrow('nicht gefunden');
  } finally { p.kill(); await p.exited; }
}, 90000);
