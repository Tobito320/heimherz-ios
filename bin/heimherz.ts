// CLI `heimherz` (SPEC 7). Hier nur die echte Verdrahtung (Umgebung, systemd-creds, bw, qrencode); die Logik steht in befehle.ts.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';
import { Meldung, eintraege, einrichtenBefehl, exportBitwarden, geraetWeg, importBitwarden, importCsv, koppelnBefehl, liste, status, type Abh } from './befehle';
import { urlAusTailscale } from './koppeln';
import { systemdCreds } from './schluessel';
import { eigenerTab, fuelleFeld, FuellFehler, handyHinweis, protokoll, waehle, wertVon, type Was } from './fuellen';
import { erlaubt, modellVon, stufenText } from './stufen';

const HILFE = `heimherz einrichten
heimherz koppeln [NAME]
heimherz import bitwarden
heimherz import csv DATEI     (Apple Passwörter oder Chrome)
heimherz export bitwarden DATEI
heimherz liste [SUCHE]
heimherz status
heimherz geraet weg ID
heimherz fuell TAB CSS benutzer|passwort|code [--konto K] [--rahmen IFRAME-CSS] [--enter] [--auftrag DATEI]
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
  if (cmd === 'geraet' && r[0] === 'weg' && r[1]) return geraetWeg(a, r[1]);
  if (cmd === 'fuell' || cmd === 'erlaubt' || cmd === 'stufen') return fuellen(a, cmd, r);
  console.error(HILFE);
  process.exitCode = 2;
}

// SPEC 23: Stufe prüfen, Eintrag wählen, Wert per CDP ins Feld; Protokoll ohne Werte, Stufe 1 meldet Ahmed am Handy.
async function fuellen(a: Abh, cmd: string, r: string[]) {
  const e = process.env, opt: Record<string, string | true> = {}, pos: string[] = [];
  for (let i = 0; i < r.length; i++) {
    if (r[i] === '--enter') opt.enter = true;
    else if (['--konto', '--rahmen', '--auftrag'].includes(r[i]) && r[i + 1]) opt[r[i].slice(2)] = r[++i];
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
