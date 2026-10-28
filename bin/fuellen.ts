// `heimherz fuell` (SPEC 23): Login-Werte aus dem Tresor direkt ins Seitenfeld eines eigenen claude-chrome-Tabs, nie in stdout, argv oder Log.
import { appendFileSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Eintrag } from '../lib/zusammenfuehren';
import { code, einstellung, restSekunden } from './totp';

export type Was = 'benutzer' | 'passwort' | 'code';
export class FuellFehler extends Error { constructor(m: string, public exit = 6) { super(m); } }

export const hostVon = (u: string) => { try { return new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(u) ? u : `https://${u}`).hostname.toLowerCase(); } catch { return ''; } };
export const seite = (h: string) => h.replace(/^www\./, '').split('.').slice(-2).join('.');   // wie Bitwarden "Basis-Domain"
const hatWert = (e: Eintrag, was: Was | 'beliebig') => was === 'beliebig' ? true : was === 'code' ? !!einstellung(e.totp) : was === 'passwort' ? !!e.passwort : !!e.benutzer;
export const zeile = (e: Eintrag) => [e.id.slice(0, 8), e.name, e.benutzer, [...new Set(e.urls.map(hostVon))].join(','), einstellung(e.totp) ? 'totp' : '-'].join(' | ');

// Doppelte (Kausar: zwei Arbeitsagentur-Einträge, TOTP nur in einem; Apple dreimal): gleiche Person = der mit dem Wert, dann mit TOTP, dann der neueste.
export function waehle(eintraege: Eintrag[], seitenUrl: string, was: Was | 'beliebig', konto?: string): Eintrag {
  const ziel = seite(hostVon(seitenUrl));
  let l = eintraege.filter(e => !e.geloescht && e.art === 'login' && e.urls.some(u => { const h = hostVon(u); return h && seite(h) === ziel; }));
  if (konto) { const k = konto.toLowerCase(); l = l.filter(e => e.id.toLowerCase().startsWith(k) || e.benutzer.toLowerCase() === k || e.name.toLowerCase().includes(k)); }
  if (!l.length) throw new FuellFehler(`Kein Heimherz-Eintrag für ${hostVon(seitenUrl)}${konto ? ' und ' + konto : ''}`);
  if (new Set(l.map(e => e.benutzer.toLowerCase())).size > 1) throw new FuellFehler(`${l.length} Einträge passen, --konto wählen:\n${l.map(zeile).join('\n')}`);
  l = l.filter(e => hatWert(e, was));
  if (!l.length) throw new FuellFehler(was === 'code' ? 'Eintrag hat keinen TOTP-Schlüssel' : 'Eintrag hat dort keinen Wert');
  return l.sort((a, b) => Number(!!einstellung(b.totp)) - Number(!!einstellung(a.totp)) || b.geaendert.localeCompare(a.geaendert))[0];
}

export async function wertVon(e: Eintrag, was: Was, jetzt = () => Date.now(), warte = (ms: number) => new Promise(r => setTimeout(r, ms))): Promise<string> {
  if (was === 'benutzer') return e.benutzer;
  if (was === 'passwort') return e.passwort;
  const t = einstellung(e.totp)!;
  if (restSekunden(t, jetzt()) < 3) await warte(restSekunden(t, jetzt()) * 1000 + 200);   // sonst läuft der Code beim Absenden ab
  return code(t, jetzt());
}

// Tab muss in den eigenen Fenstern liegen (claude-chrome tabs zeigt nur eigene) und https sein.
export function eigenerTab(tabsText: string, tab: string, httpsPflicht = true): { id: string; url: string } {
  const z = tabsText.split('\n').map(l => l.trim().split(/\s{2,}/)).find(p => p[0] && (p[0].startsWith(tab) || p[p.length - 1].includes(tab)));
  if (!z) throw new FuellFehler(`Tab "${tab}" nicht in deinen Fenstern (claude-chrome tabs)`, 2);
  const url = z[z.length - 1];
  if (httpsPflicht && !/^https:\/\//.test(url)) throw new FuellFehler('Nur https-Seiten', 2);
  return { id: z[0], url };
}

export async function cdp(port: number, tabId: string) {
  const t = ((await (await fetch(`http://127.0.0.1:${port}/json`)).json()) as any[]).find(x => x.id.startsWith(tabId) && x.type === 'page');
  if (!t) throw new FuellFehler('Tab ist weg', 5);
  const ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new FuellFehler('CDP nicht erreichbar', 2)); });
  let n = 0; const offen: Record<number, (d: any) => void> = {};
  ws.onmessage = m => { const d = JSON.parse(String(m.data)); offen[d.id]?.(d); delete offen[d.id]; };
  const send = (method: string, params = {}) => new Promise<any>((r, j) => {
    const i = ++n;
    const uhr = setTimeout(() => { delete offen[i]; j(new FuellFehler(`CDP Zeit (${method})`, 4)); }, 10000);   // sonst hält der Zeitgeber den Prozess 10 s am Leben
    offen[i] = d => { clearTimeout(uhr); d.error ? j(new FuellFehler('CDP: ' + String(d.error.message).slice(0, 80))) : r(d.result); };
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  const val = async (expr: string) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.value;
  return { send, val, close: () => ws.close() };
}

// Wie claude-bw: erst prüfen, ob die Bitwarden-Erweiterung schon gefüllt hat (sonst doppelt), dann Input.insertText, dann gegenprüfen.
export async function fuelleFeld(o: { port: number; tabId: string; css: string; rahmen?: string; enter?: boolean }, text: string): Promise<{ laenge: number; schon: boolean }> {
  const c = await cdp(o.port, o.tabId), sel = JSON.stringify(o.css);
  const d = o.rahmen ? `document.querySelector(${JSON.stringify(o.rahmen)})?.contentDocument` : 'document';
  const t = JSON.stringify(text);
  try {
    const fokus = `(()=>{const e=${d}?.querySelector(${sel});if(!e||e.disabled)return 0;e.scrollIntoView({block:'center'});e.focus();return ${d}.activeElement===e?1:0})()`;
    const leeren = `(()=>{const e=${d}.querySelector(${sel});Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e),'value').set.call(e,'');e.dispatchEvent(new Event('input',{bubbles:true}));e.focus();return 1})()`;
    const drin = () => c.val(`${d}.querySelector(${sel}).value===${t}`);
    if (await c.val(fokus) !== 1) throw new FuellFehler('Feld nicht gefunden oder nicht fokussierbar');
    let schon = await drin();
    for (let i = 0; !schon && i < 2; i++) {
      await c.val(leeren);
      await c.send('Input.insertText', { text });
      if (await drin()) break;
      if (i === 1) { const len = await c.val(`${d}.querySelector(${sel}).value.length`); await c.val(leeren); throw new FuellFehler(`Feld hat ${len} statt ${text.length} Zeichen, geleert`); }
    }
    if (o.enter) for (const type of ['keyDown', 'keyUp']) await c.send('Input.dispatchKeyEvent', { type, key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13, ...(type === 'keyDown' ? { text: '\r' } : {}) });
    return { laenge: text.length, schon };
  } finally { c.close(); }
}

// totp-setzen: neuer Schlüssel in den Eintrag; der alte geht in `totpVerlauf` (eigenes Feld, damit der Passwort-Verlauf der App keine Schlüssel zeigt).
export function mitTotp(e: Eintrag, roh: string, jetzt = new Date()): Eintrag {
  const t = einstellung(roh);
  if (!t || t.geheim.length < 16) throw new FuellFehler('Kein gültiger Base32-Schlüssel (mindestens 16 Zeichen), nichts gespeichert');
  if (einstellung(e.totp)?.geheim === t.geheim) return e;
  const bis = jetzt.toISOString();
  const verlauf = e.totp ? { totpVerlauf: [{ totp: e.totp, bis }, ...((e.totpVerlauf as unknown[]) ?? [])].slice(0, 5) } : {};
  return { ...e, ...verlauf, totp: /^otpauth:/i.test(roh.trim()) ? roh.trim() : t.geheim, geaendert: bis };
}

// Einrichtungsschlüssel von der Seite: aus --feld, sonst der eine sichtbare Text, der wie ein Schlüssel aussieht (auch in Gruppen-Spans; gleiche Schlüssel zählen einmal).
export async function leseSchluessel(o: { port: number; tabId: string; feld?: string }): Promise<string> {
  const c = await cdp(o.port, o.tabId);
  try {
    if (o.feld) return String(await c.val(`(()=>{const e=document.querySelector(${JSON.stringify(o.feld)});return e?(e.value??e.innerText??''):''})()`) ?? '').trim();
    const kandidaten: string[] = await c.val(`(()=>{
      const muster=[/^(?:[a-z2-7]{4} ){3,}[a-z2-7]{1,8}$/i,/^[A-Z2-7]{16,}=*$/,/^(?=.*[2-7])[a-z2-7]{16,}$/];
      const sichtbar=e=>e.getClientRects().length>0;
      const t=[...document.querySelectorAll('body *')].filter(sichtbar).map(e=>(e.innerText||'').slice(0,200))
        .concat([...document.querySelectorAll('input,textarea')].filter(sichtbar).map(e=>e.value||''))
        .map(x=>x.trim().replace(/\\s+/g,' ')).filter(x=>muster.some(m=>m.test(x)));
      return t.concat([...document.querySelectorAll('a[href^="otpauth:"]')].map(a=>a.href));
    })()`) ?? [];
    const eindeutig = new Map(kandidaten.map(k => [einstellung(k)?.geheim ?? '', k]).filter(([g]) => g.length >= 16));
    if (eindeutig.size !== 1) throw new FuellFehler(eindeutig.size ? `${eindeutig.size} mögliche Schlüssel auf der Seite, --feld CSS angeben` : 'Kein Einrichtungsschlüssel sichtbar (erst "Schlüssel anzeigen"/"Kann nicht scannen" öffnen oder --feld CSS)');
    return [...eindeutig.values()][0];
  } finally { c.close(); }
}

// Nie Werte: nur wer, wo, was, ob erlaubt.
export function protokoll(ordner: string, z: { host: string; id?: string; was: string; stufe: number; modell: string; ok: boolean; grund: string; auftrag?: string }) {
  mkdirSync(ordner, { recursive: true, mode: 0o700 });
  appendFileSync(join(ordner, 'fuell.log'), [new Date().toISOString(), z.host, z.id?.slice(0, 8) ?? '-', z.was, `stufe ${z.stufe}`, z.modell, z.ok ? 'erlaubt' : 'verweigert', z.grund.replace(/\s+/g, ' '), z.auftrag ?? '-'].join('\t') + '\n', { mode: 0o600 });
}

// Mitteilung ans Handy über den Zappy-Helfer ($XDG_RUNTIME_DIR/zentrale-hinweis/*.json, der neueste wird gezeigt)
export function handyHinweis(laufzeit: string, titel: string, text: string, ttlS = 900) {
  if (!laufzeit) return;
  const ordner = join(laufzeit, 'zentrale-hinweis');
  mkdirSync(ordner, { recursive: true, mode: 0o700 });
  const datei = join(ordner, `heimherz-${crypto.randomUUID().slice(0, 12)}.json`);
  writeFileSync(`${datei}.tmp`, JSON.stringify({ titel: titel.slice(0, 60), text: text.slice(0, 200), ablauf: Date.now() + ttlS * 1000 }), { mode: 0o600 });
  renameSync(`${datei}.tmp`, datei);
}
