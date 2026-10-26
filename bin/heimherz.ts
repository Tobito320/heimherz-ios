// CLI `heimherz` (SPEC 7). Hier nur die echte Verdrahtung (Umgebung, systemd-creds, bw, qrencode); die Logik steht in befehle.ts.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';
import { Meldung, eintraege, fotosAnalyse, fotosGruppen, fotosVorschlag, einrichtenBefehl, exportBitwarden, geraetWeg, importBitwarden, importCsv, koppelnBefehl, liste, status, totpSetzen, type Abh } from './befehle';
import { urlAusTailscale } from './koppeln';
import { systemdCreds } from './schluessel';
import { eigenerTab, fuelleFeld, FuellFehler, handyHinweis, leseSchluessel, protokoll, waehle, wertVon, type Was } from './fuellen';
import { erlaubt, modellVon, stufenText } from './stufen';
import { fasseTempo, leseTempo } from './tempo';

const HILFE = `heimherz einrichten
heimherz koppeln [NAME]
heimherz import bitwarden
heimherz import csv DATEI     (Apple Passwörter oder Chrome)
heimherz export bitwarden DATEI
heimherz liste [SUCHE]
heimherz status
heimherz tempo [MINUTEN]    (Foto-Abgleich: wo hängt die Zeit, Standard 10)
heimherz fotos analyse    (Duplikate, Ähnliche, Unscharfe rechnen, nur Zahlen)
heimherz fotos gruppen [--json]
heimherz fotos vorschlag KENNUNG BEHALTEN --grund TEXT   (KENNUNG = irgendein Mitglied der Gruppe)
heimherz geraet weg ID
heimherz fuell TAB CSS benutzer|passwort|code [--konto K] [--rahmen IFRAME-CSS] [--enter] [--auftrag DATEI]
heimherz totp-setzen TAB --konto K [--feld CSS]   (Einrichtungsschlüssel der Seite in den Eintrag)
heimherz erlaubt HOST [--auftrag DATEI]   (Exit 0 erlaubt, 7 verweigert)
heimherz stufen`;

async function ausgabeVon(argv: string[], env?: Record<string, string | undefined>, stdin?: string): Promise<string> {
  const p = Bun.spawn(argv, { stdin: stdin === undefined ? 'ignore' : 'pipe', stdout: 'pipe', stderr: 'ignore', env: env ?? process.env });
  if (stdin !== undefined) { p.stdin!.write(stdin); await p.stdin!.end(); }
  const [aus, rc] = await Promise.all([new Response(p.stdout).text(), p.exited]);
  if (rc !== 0) throw new Error(`${argv[0]} schlug fehl (${rc})`);
  return aus;
}

// Bitwarden-Sitzung von claude-bw; fehlt sie oder ist sie abgelaufen, ist der Tresor gesperrt. Ausgabe nur in den Speicher.
async function bwJson(): Promise<string> {
  const laufzeit = process.env.XDG_RUNTIME_DIR ?? '';
  const sitzung = join(laufzeit, 'claude-bw/session');
  const gesperrt = new Meldung('Bitwarden gesperrt: claude-bw entsperre');
  if (!isAbsolute(laufzeit) || !existsSync(sitzung)) throw gesperrt;
  const env = { ...process.env, BITWARDENCLI_APPDATA_DIR: join(homedir(), '.config/claude-bw'), BW_SESSION: readFileSync(sitzung, 'utf8').trim() };
  try {
    await ausgabeVon(['bw', 'sync', '--nointeraction'], env); // lokaler Cache kann veraltet sein (claude-bw synct aus demselben Grund)
    return await ausgabeVon(['bw', 'list', 'items', '--raw', '--nointeraction'], env);
  } catch { throw gesperrt; }
}

// Gibt zurück, wie man den Betrachter wieder schließt (koppeln ruft es im finally): claude-start druckt die Fensteradresse, die schließt hyprctl.
async function anzeigen(datei: string): Promise<() => void> {
  if (!Bun.which('claude-start')) {
    const p = Bun.spawn(['xdg-open', datei], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' }); // shortcut: schließt nur xdg-open selbst, nicht den Betrachter
    return () => p.kill();
  }
  const adresse = (await ausgabeVon(['claude-start', '--fuer-ahmed', 'imv', datei])).trim();
  return () => {
    if (/^0x[0-9a-f]+$/.test(adresse)) Bun.spawn(['hyprctl', 'dispatch', 'closewindow', `address:${adresse}`], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' }).unref();
  };
}

async function main(argv: string[]) {
  const e = process.env;
  const a: Abh = {
    daten: e.HEIMHERZ_DATEN ?? join(homedir(), '.local/share/heimherz'),
    fotos: e.HEIMHERZ_FOTOS ?? join(homedir(), 'Heimherz/Fotos'),
    dateien: e.HEIMHERZ_DATEIEN ?? join(homedir(), 'Heimherz/Dateien'),
    dienstUrl: `http://127.0.0.1:${e.HEIMHERZ_PORT ?? 8790}`,
    creds: systemdCreds,
    ausgabe: z => console.log(z),
  };
  const [cmd, ...r] = argv;
  if (cmd === 'einrichten') return einrichtenBefehl(a);
  if (cmd === 'koppeln') {
    const abbruch = new AbortController();
    for (const s of ['SIGINT', 'SIGTERM'] as const) process.on(s, () => abbruch.abort());
    const url = e.HEIMHERZ_URL ?? urlAusTailscale(await ausgabeVon(['tailscale', 'status', '--json']));
    const ok = await koppelnBefehl(a, r[0] ?? 'handy', {
      url, laufzeit: e.XDG_RUNTIME_DIR ?? '', abbruch: abbruch.signal, zeige: anzeigen,
      qrencode: async (nutzlast, datei) => { await ausgabeVon(['qrencode', '-o', datei, '-s', '10'], undefined, nutzlast); },
    });
    if (!ok) process.exitCode = 1;
    return;
  }
  if (cmd === 'import' && r[0] === 'bitwarden') return importBitwarden(a, bwJson);
  if (cmd === 'import' && r[0] === 'csv' && r[1]) return importCsv(a, r[1]);
  if (cmd === 'export' && r[0] === 'bitwarden' && r[1]) return exportBitwarden(a, r[1]);
  if (cmd === 'liste') return liste(a, r[0]);
  if (cmd === 'status') return status(a);
  if (cmd === 'tempo') { for (const z of fasseTempo(leseTempo(a.daten), Number(r[0]) > 0 ? Number(r[0]) : 10)) a.ausgabe(z); return; }
  if (cmd === 'fotos' && r[0] === 'analyse') return fotosAnalyse(a);
  if (cmd === 'fotos' && r[0] === 'gruppen') return fotosGruppen(a, r.includes('--json'));
  if (cmd === 'fotos' && r[0] === 'vorschlag' && r[1] && r[2]) { const i = r.indexOf('--grund'); return fotosVorschlag(a, r[1], r[2], i > 0 ? r.slice(i + 1).join(' ') : ''); }
  if (cmd === 'geraet' && r[0] === 'weg' && r[1]) return geraetWeg(a, r[1]);
  if (cmd === 'fuell' || cmd === 'totp-setzen' || cmd === 'erlaubt' || cmd === 'stufen') return fuellen(a, cmd, r);
  console.error(HILFE);
  process.exitCode = 2;
}

// SPEC 23: Stufe prüfen, Eintrag wählen, Wert per CDP ins Feld; Protokoll ohne Werte, Stufe 1 meldet Ahmed am Handy.
async function fuellen(a: Abh, cmd: string, r: string[]) {
  const e = process.env, opt: Record<string, string | true> = {}, pos: string[] = [];
  for (let i = 0; i < r.length; i++) {
    if (r[i] === '--enter') opt.enter = true;
    else if (['--konto', '--rahmen', '--auftrag', '--feld'].includes(r[i]) && r[i + 1]) opt[r[i].slice(2)] = r[++i];
    else pos.push(r[i]);
  }
  const auftrag = (opt.auftrag as string | undefined) ?? e.HEIMHERZ_AUFTRAG;
  const modell = modellVon(e);
  if (cmd === 'stufen') { a.ausgabe(stufenText()); a.ausgabe(`Diese Sitzung: ${modell}`); return; }
  const state = join(e.XDG_STATE_HOME ?? join(homedir(), '.local/state'), 'heimherz');
  if (cmd === 'erlaubt') {
    if (!pos[0]) { console.error(HILFE); process.exitCode = 2; return; }
    const u = erlaubt(pos[0].replace(/^https?:\/\//, '').split('/')[0], modell, auftrag, e);
    a.ausgabe(`${u.ok ? 'erlaubt' : 'verweigert'}: ${u.grund}`);
    if (!u.ok) { protokoll(state, { host: pos[0], was: 'erlaubt', stufe: u.stufe, modell, ok: false, grund: u.grund, auftrag }); process.exitCode = 7; }
    return;
  }
  if (cmd === 'totp-setzen') {
    if (!pos[0] || !opt.konto) { console.error(HILFE); process.exitCode = 2; return; }
    try {
      const t = eigenerTab(await ausgabeVon(['claude-chrome', 'tabs']), pos[0]);
      const host = new URL(t.url).hostname;
      const u = erlaubt(host, modell, auftrag, e);
      if (!u.ok) { protokoll(state, { host, was: 'totp-setzen', stufe: u.stufe, modell, ok: false, grund: u.grund, auftrag }); throw new FuellFehler(`verweigert: ${u.grund}`, 7); }
      const it = waehle(await eintraege(a), t.url, 'benutzer', opt.konto as string);
      let roh = await leseSchluessel({ port: Number(e.HEIMHERZ_CDP_PORT ?? 9333), tabId: t.id, feld: opt.feld as string | undefined });
      try {
        const neu = await totpSetzen(a, it.id, roh);
        protokoll(state, { host, id: it.id, was: 'totp-setzen', stufe: u.stufe, modell, ok: true, grund: u.grund, auftrag });
        a.ausgabe(`${neu ? 'gesetzt' : 'war schon gesetzt'}: ${it.name} (${host})`);
      } finally { roh = ''; }
    } catch (err) {
      if (err instanceof FuellFehler) { console.error(`heimherz: ${err.message}`); process.exitCode = err.exit; return; }
      throw err;
    }
    return;
  }
  const [tab, css, was] = pos;
  if (!tab || !css || !['benutzer', 'passwort', 'code'].includes(was)) { console.error(HILFE); process.exitCode = 2; return; }
  try {
    const t = eigenerTab(await ausgabeVon(['claude-chrome', 'tabs']), tab);
    const host = new URL(t.url).hostname;
    const u = erlaubt(host, modell, auftrag, e);
    if (!u.ok) { protokoll(state, { host, was, stufe: u.stufe, modell, ok: false, grund: u.grund, auftrag }); throw new FuellFehler(`verweigert: ${u.grund}`, 7); }
    const it = waehle(await eintraege(a), t.url, was as Was, opt.konto as string | undefined);
    let wert = await wertVon(it, was as Was);
    try {
      const f = await fuelleFeld({ port: Number(e.HEIMHERZ_CDP_PORT ?? 9333), tabId: t.id, css, rahmen: opt.rahmen as string | undefined, enter: !!opt.enter }, wert);
      protokoll(state, { host, id: it.id, was, stufe: u.stufe, modell, ok: true, grund: u.grund, auftrag });
      if (u.stufe === 1) handyHinweis(e.XDG_RUNTIME_DIR ?? '', 'Sparkasse: Agent meldet sich an', `${modell}-Sitzung füllt ${was} auf ${host} (Auftrag ${auftrag?.split('/').pop()})`);
      a.ausgabe(`ok: ${was} (${it.benutzer || it.name}) ${f.laenge} Zeichen in ${host}${f.schon ? ' (war schon drin)' : ''}${opt.enter ? ', Enter' : ''}`);
    } finally { wert = ''; }
  } catch (err) {
    if (err instanceof FuellFehler) { console.error(`heimherz: ${err.message}`); process.exitCode = err.exit; return; }
    throw err;
  }
}

main(process.argv.slice(2)).catch(err => {
  console.error(err instanceof Meldung ? err.message : `Fehler: ${err?.message ?? err}`);
  process.exit(1);
});
