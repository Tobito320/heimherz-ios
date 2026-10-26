// `heimherz login` und `heimherz merke` (SPEC 26): ganzer Login in einem Aufruf, Passwort-Umzug von der Handy-Karte in den Tresor.
// Werte gehen nur per CDP ins Feld oder aus dem Feld in den Tresor, nie in stdout, argv, Log oder Gedächtnis.
import { chmodSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Eintrag } from '../lib/zusammenfuehren';
import { cdp, fuelleFeld, FuellFehler, type Was } from './fuellen';

export type Ergebnis = 'eingeloggt' | 'falsches-passwort' | '2fa' | 'captcha' | 'unbekannt';
export const LOGIN_EXIT: Record<Ergebnis, number> = { eingeloggt: 0, 'falsches-passwort': 8, '2fa': 9, captcha: 10, unbekannt: 11 };
export type Rolle = 'benutzer' | 'passwort' | 'code' | 'absenden';
export type Selektoren = Partial<Record<Rolle, string>>;
export type Gedaechtnis = Selektoren & { erfolgPfad?: string; zuletzt?: string };
export type Zustand = Selektoren & { url: string; captcha: boolean; fehler: boolean; kauf: boolean; wartet: boolean };

// Dieselbe Kauf-Sperre wie in claude-chrome (KAUF_RE/KAUF_FORM, 16.10.: "ai darf niemals kaufen"): ein Absende-Knopf, der kauft, wird nie geklickt.
export const KAUF_RE = /\b(?:(?:jetzt |sofort )?kaufen|(?:jetzt )?bezahlen|zur kasse|checkout|purchase|buy(?: now)?|pay(?: now)?|(?:kosten|zahlungs)pflichtig bestellen|bestellung (?:abschicken|aufgeben|abschlie(?:ß|ss)en)|place (?:your )?order|complete (?:your )?(?:order|purchase)|guthaben aufladen|(?:add|buy) credits|top[- ]?up|abo abschlie(?:ß|ss)en|(?:jetzt )?abonnieren|subscribe)\b/i;
export const KAUF_FORM = /(?:checkout|payment|purchase|bezahl|kasse)/i;

// Läuft in der Seite. Erst gemerkte Selektoren (müssen noch zur Rolle passen), dann Suche nach Typ, autocomplete und Beschriftung.
// shortcut: nur das Hauptdokument, kein Shadow-DOM und keine iframes; dann Felder von Hand mit `heimherz fuell --rahmen`.
export const SCAN_JS = (bekannt: Selektoren) => `(()=>{
  const B=${JSON.stringify(bekannt)};
  const sichtbar=e=>{if(!e.getClientRects().length)return false;const s=getComputedStyle(e);return s.visibility!=='hidden'&&s.display!=='none'};
  const sel=e=>{
    const eindeutig=s=>{try{return document.querySelectorAll(s).length===1}catch(x){return false}};
    if(e.id&&eindeutig('#'+CSS.escape(e.id)))return '#'+CSS.escape(e.id);
    for(const a of ['name','data-testid','autocomplete','aria-label']){const v=e.getAttribute(a);if(v){const s=e.tagName.toLowerCase()+'['+a+'='+JSON.stringify(v)+']';if(eindeutig(s))return s}}
    const teile=[];for(let n=e;n&&n.nodeType===1&&n!==document.body;n=n.parentElement){const i=[...n.parentElement.children].filter(k=>k.tagName===n.tagName).indexOf(n)+1;teile.unshift(n.tagName.toLowerCase()+':nth-of-type('+i+')')}
    return 'body > '+teile.join(' > ');
  };
  const ok=s=>{if(!s)return null;try{const e=document.querySelector(s);return e&&sichtbar(e)&&!e.disabled?e:null}catch(x){return null}};
  const ein=[...document.querySelectorAll('input,textarea')].filter(e=>sichtbar(e)&&!e.disabled&&!e.readOnly&&!['hidden','checkbox','radio','submit','button','image','file','search','reset'].includes(e.type));
  const txt=e=>[e.name,e.id,e.getAttribute('autocomplete'),e.getAttribute('aria-label'),e.placeholder,e.labels&&e.labels[0]?e.labels[0].innerText:''].join(' ').toLowerCase();
  const codeTxt=/(^|[^a-z])(otp|totp|2fa|mfa|tan|pin|code|token|authenticator)([^a-z]|$)|one-time|verif|sicherheitscode|bestätigungscode|bestaetigungscode/;
  const istCode=e=>e.type!=='password'&&(e.autocomplete==='one-time-code'||codeTxt.test(txt(e))||(e.inputMode==='numeric'&&e.maxLength>=4&&e.maxLength<=8));
  const pwB=ok(B.passwort),pwS=ein.filter(e=>e.type==='password'),pw=(pwB&&pwB.type==='password'?pwB:null)||pwS.find(e=>e.autocomplete==='current-password')||pwS[0]||null;
  const cB=ok(B.code),code=(cB&&cB.type!=='password'?cB:null)||ein.find(istCode)||null;
  const bB=ok(B.benutzer),texte=ein.filter(e=>e!==code&&['text','email','tel','url','number',''].includes(e.type));
  const ben=(bB&&bB.type!=='password'&&bB!==code?bB:null)||texte.find(e=>/username|email/.test(e.autocomplete))||texte.find(e=>/user|mail|login|konto|benutzer|kennung|nutzer|account|identifier|uname/.test(txt(e)))||(pw?texte[0]:null)||null;
  const anker=pw||code||ben,wurzel=(anker&&anker.form)||document;
  const knopfText=e=>((e.innerText||e.value||e.getAttribute('aria-label')||'')+'').trim().toLowerCase();
  // "Mit Passkey anmelden" ist ein anderer Weg als Benutzer und Passwort: nie als Absende-Knopf nehmen (sso.arbeitsagentur.de).
  const knoepfe=[...wurzel.querySelectorAll('button,input[type=submit],[role=button]')].filter(e=>sichtbar(e)&&!e.disabled&&e.getAttribute('aria-disabled')!=='true'&&!/passkey|webauthn|sicherheitsschlüssel|security key/.test(knopfText(e)));
  const abB=ok(B.absenden);
  const ab=(abB&&anker&&!/passkey|webauthn/.test(knopfText(abB))?abB:null)||knoepfe.find(e=>e.type==='submit')||knoepfe.find(e=>/^(anmelden|einloggen|login|log in|sign in)$/.test(knopfText(e)))||knoepfe.find(e=>/anmelden|einloggen|login|log in|sign in|weiter|continue|next|senden|bestätigen|verify|submit|absenden/.test(knopfText(e)))||null;
  const KAUF=new RegExp(${JSON.stringify(KAUF_RE.source)},'i'),KAUF_FORM=new RegExp(${JSON.stringify(KAUF_FORM.source)},'i');
  const lbl=ab?knopfText(ab).replace(/\\s+/g,' '):'';
  const kauf=!!ab&&((lbl.length>0&&lbl.length<=80&&KAUF.test(lbl))||(!lbl&&!!ab.form&&KAUF_FORM.test(ab.form.action||'')));
  const wartet=/(bestätige|bestätigen|genehmige|approve|check your (phone|device)|prüfe dein (handy|gerät)|auf deinem (handy|gerät)).{0,80}(app|handy|gerät|phone|device|benachrichtigung|notification)/i.test((document.body?document.body.innerText:'').slice(0,3000));
  const captcha=!![...document.querySelectorAll('iframe[src*=recaptcha],iframe[src*=hcaptcha],iframe[src*=turnstile],iframe[src*=captcha],.g-recaptcha,.h-captcha,.cf-turnstile')].find(e=>!e.closest('.grecaptcha-badge')&&sichtbar(e))
    ||/captcha|ich bin kein roboter|not a robot|verify you are human|bist du ein mensch/i.test((document.body?document.body.innerText:'').slice(0,3000));
  const fehler=[...document.querySelectorAll('[role=alert],[class*=error],[class*=fehler],[id*=error],[id*=fehler],.alert,[aria-invalid=true]')]
    .some(e=>sichtbar(e)&&/falsch|ungültig|ungueltig|incorrect|invalid|wrong|fehlgeschlagen|nicht korrekt|stimmt nicht|failed|denied|nicht erkannt|gesperrt|locked/i.test(e.innerText||''));
  return {url:location.origin+location.pathname,captcha,fehler,kauf,wartet,benutzer:ben?sel(ben):undefined,passwort:pw?sel(pw):undefined,code:code?sel(code):undefined,absenden:ab?sel(ab):undefined};
})()`;

type C = Awaited<ReturnType<typeof cdp>>;
const scanne = async (c: C, bekannt: Selektoren): Promise<Zustand> => await c.val(SCAN_JS(bekannt));
const unterschrift = (z: Zustand) => [z.url, z.benutzer ? 'b' : '', z.passwort ? 'p' : '', z.code ? 'c' : '', z.captcha ? 'k' : '', z.fehler ? 'f' : ''].join('|');

// Echter Mausklick auf die Mitte (vertrauenswürdiges Ereignis, anders als el.click()); ohne Knopf Enter im zuletzt gefüllten Feld.
async function absenden(c: C, z: Zustand, letztes: string) {
  const mitte = z.absenden ? await c.val(`(()=>{const e=document.querySelector(${JSON.stringify(z.absenden)});if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return[r.x+r.width/2,r.y+r.height/2]})()`) as [number, number] | null : null;
  if (mitte) {
    for (const type of ['mousePressed', 'mouseReleased']) await c.send('Input.dispatchMouseEvent', { type, x: mitte[0], y: mitte[1], button: 'left', clickCount: 1 });
    return;
  }
  await c.val(`document.querySelector(${JSON.stringify(letztes)})?.focus()`);
  for (const type of ['keyDown', 'keyUp']) await c.send('Input.dispatchKeyEvent', { type, key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, ...(type === 'keyDown' ? { text: '\r' } : {}) });
}

export type LoginOpt = {
  port: number; tabId: string; mitCode: boolean; bekannt?: Gedaechtnis;
  wert: (was: Was) => Promise<string>;   // holt den Wert erst, wenn das Feld da ist (TOTP wartet sonst unnötig)
  warteMs?: number;                      // so lange auf eine Änderung der Seite nach dem Absenden warten
  beruhigtMs?: number;                   // so lange muss eine Seite ohne Felder so bleiben, bevor sie als fertig gilt
};
export type LoginAntwort = { ergebnis: Ergebnis; hinweis: string; benutzt: Selektoren; url?: string; erfolgPfad?: string; passwortFeld?: string };

export async function loginAblauf(o: LoginOpt): Promise<LoginAntwort> {
  const c = await cdp(o.port, o.tabId), benutzt: Selektoren = {}, gefuellt = new Set<Was>();
  const ende = (ergebnis: Ergebnis, hinweis: string, z?: Zustand): LoginAntwort => ({ ergebnis, hinweis, benutzt, url: z?.url, passwortFeld: z?.passwort ?? benutzt.passwort, ...(ergebnis === 'eingeloggt' && z ? { erfolgPfad: z.url } : {}) });
  const keineFelder = (z: Zustand) => !z.benutzer && !z.passwort && !z.code && !z.captcha;
  // Ohne Felder kann die Seite noch laden (mehrstufige Logins holen Schritt 2 oft erst per XHR): erst entscheiden, wenn sie eine Sekunde so bleibt.
  const beruhigt = async (z: Zustand) => { if (!keineFelder(z)) return z; await Bun.sleep(o.beruhigtMs ?? 1000); return scanne(c, { ...o.bekannt, ...benutzt }); };
  try {
    let z = await beruhigt(await scanne(c, o.bekannt ?? {})), letztes = '', urlVorSubmit = '';
    for (let runde = 0; runde < 5; runde++) {
      if (z.captcha) return ende('captcha', 'Captcha sichtbar, das macht Ahmed', z);
      if (z.kauf) return ende('unbekannt', 'Absende-Knopf sieht nach Kaufen aus: nie, Ahmed klickt selbst', z);
      if (runde > 0 && z.fehler && gefuellt.has('passwort')) return ende('falsches-passwort', 'Seite zeigt eine Fehlermeldung', z);
      let neu = false;
      for (const was of ['benutzer', 'passwort', 'code'] as const) {
        const css = z[was];
        if (!css || gefuellt.has(was)) continue;
        if (was === 'code' && !o.mitCode) return ende('2fa', `Code-Feld ${css}: mit --code wiederholen (Eintrag braucht TOTP)`, z);
        const wert = await o.wert(was);
        if (!wert) throw new FuellFehler(`Eintrag hat keinen Wert für ${was}, die Seite verlangt ihn (${css}); nichts gefüllt`);   // sonst meldet die Seite "falsch" und Ahmed bekommt eine unnötige Karte
        await fuelleFeld({ port: o.port, tabId: o.tabId, css }, wert);
        gefuellt.add(was); benutzt[was] = css; letztes = css; neu = true;
      }
      if (!neu) {
        if (z.wartet) return ende('unbekannt', 'Seite wartet auf eine Bestätigung am Handy oder in einer App', z);
        if (keineFelder(z)) {
          if (!gefuellt.size && o.bekannt?.erfolgPfad !== z.url) return ende('unbekannt', 'keine Anmeldefelder und nichts gefüllt: Seite lädt, ist schon eingeloggt oder fremd (claude-chrome sieh)', z);
          return ende('eingeloggt', 'keine Anmeldefelder mehr', z);
        }
        if (!z.passwort && !z.code && o.bekannt?.erfolgPfad === z.url) return ende('eingeloggt', 'bekannter Erfolgspfad', z);
        if (z.passwort && gefuellt.has('passwort') && !z.code) {
          // Der Erfolg kommt manchmal vor dem Abbau der Seite (Mark-E: schon /portal/dashboard, Passwortfeld noch kurz da): erst nachsehen, dann Exit 8.
          const vorNachsicht = unterschrift(z);
          for (let i = 0; i < 3; i++) {
            await Bun.sleep(o.beruhigtMs ?? 1000);
            z = await scanne(c, { ...o.bekannt, ...benutzt });
            if (z.fehler) return ende('falsches-passwort', 'Seite zeigt eine Fehlermeldung', z);
            if (keineFelder(z)) return ende('eingeloggt', 'Seite hat sich nach kurzer Wartezeit geleert', z);
            if (o.bekannt?.erfolgPfad === z.url && !z.passwort) return ende('eingeloggt', 'bekannter Erfolgspfad', z);
          }
          if (unterschrift(z) !== vorNachsicht) continue;   // ein neuer Schritt (zum Beispiel Code) ist erschienen
          if (z.url !== urlVorSubmit) return ende('unbekannt', `Adresse wechselte zu ${z.url}, das Passwortfeld steht noch: mit claude-chrome sieh prüfen`, z);
          return ende('falsches-passwort', 'Passwortfeld ist nach dem Absenden noch da', z);
        }
        return ende('unbekannt', z.code ? 'Code abgelehnt oder Seite wartet noch' : 'Seite bleibt auf dem Anmeldefeld', z);
      }
      z = await scanne(c, { ...o.bekannt, ...benutzt });   // Absende-Knopf erst nach dem Füllen (wird oft erst dann aktiv)
      if (z.kauf) return ende('unbekannt', 'Absende-Knopf sieht nach Kaufen aus: nie, Ahmed klickt selbst', z);
      if (z.absenden) benutzt.absenden = z.absenden;
      const vorher = unterschrift(z);
      urlVorSubmit = z.url;
      await absenden(c, z, letztes);
      const bis = Date.now() + (o.warteMs ?? 8000);
      do { await Bun.sleep(300); z = await scanne(c, { ...o.bekannt, ...benutzt }); } while (unterschrift(z) === vorher && Date.now() < bis);
      z = await beruhigt(z);
    }
    return ende('unbekannt', 'mehr als 5 Schritte', z);
  } finally { c.close(); }
}

// Login-Gedächtnis (W-034): je Host Selektoren und Erfolgspfad, nie Werte. Datei 0600 im Statusordner.
const datei = (ordner: string) => join(ordner, 'login-gedaechtnis.json');
export function leseGedaechtnis(ordner: string): Record<string, Gedaechtnis> {
  try { return JSON.parse(readFileSync(datei(ordner), 'utf8')); } catch { return {}; }
}
export function merkeSeite(ordner: string, host: string, a: LoginAntwort, jetzt = new Date()) {
  if (a.ergebnis !== 'eingeloggt' || !Object.keys(a.benutzt).length) return;
  mkdirSync(ordner, { recursive: true, mode: 0o700 });
  const alle = leseGedaechtnis(ordner);
  const stabil = Object.fromEntries(Object.entries(a.benutzt).filter(([, s]) => !s.startsWith('body > ')));   // Pfade ohne id/name brechen beim nächsten Umbau
  alle[host] = { ...alle[host], ...stabil, ...(a.erfolgPfad ? { erfolgPfad: a.erfolgPfad } : {}), zuletzt: jetzt.toISOString() };
  const tmp = `${datei(ordner)}.tmp`;
  writeFileSync(tmp, JSON.stringify(alle, null, 1), { mode: 0o600 }); chmodSync(tmp, 0o600); renameSync(tmp, datei(ordner));
}

// `merke`: Wert eines Feldes, das Ahmed per Handy-Karte gefüllt hat, direkt per CDP lesen (nur im Speicher).
export async function liesFeld(o: { port: number; tabId: string; css: string; rahmen?: string }): Promise<string> {
  const c = await cdp(o.port, o.tabId);
  try {
    const d = o.rahmen ? `document.querySelector(${JSON.stringify(o.rahmen)})?.contentDocument` : 'document';
    const w = await c.val(`(()=>{const e=${d}?.querySelector(${JSON.stringify(o.css)});return e&&'value' in e?e.value:null})()`);
    if (w === null || w === undefined) throw new FuellFehler('Feld nicht gefunden');
    if (!w) throw new FuellFehler('Feld ist leer, nichts gespeichert');
    return String(w);
  } finally { c.close(); }
}

// Neues Passwort in den Eintrag; das alte geht in `passwortVerlauf` (gleiche Form wie apple.ts und die App, höchstens 5).
export function mitPasswort(e: Eintrag, neu: string, jetzt = new Date()): Eintrag {
  if (!neu) throw new FuellFehler('Leeres Passwort, nichts gespeichert');
  if (e.passwort === neu) return e;
  const bis = jetzt.toISOString();
  const verlauf = e.passwort ? { passwortVerlauf: [{ passwort: e.passwort, bis }, ...((e.passwortVerlauf as unknown[]) ?? [])].slice(0, 5) } : {};
  return { ...e, ...verlauf, passwort: neu, geaendert: bis };
}
