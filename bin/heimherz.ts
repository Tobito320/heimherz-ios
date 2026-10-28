// CLI `heimherz` (SPEC 7). Hier nur die echte Verdrahtung (Umgebung, systemd-creds, bw, qrencode); die Logik steht in befehle.ts.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';
import { Meldung, eintraege, einrichtenBefehl, exportBitwarden, geraetWeg, importBitwarden, importCsv, eintragWeg, eintragZurueck, koppelnBefehl, liste, passwortSetzen, status, totpSetzen, type Abh } from './befehle';
import { urlAusTailscale } from './koppeln';
import { systemdCreds } from './schluessel';
import { LOGIN_EXIT, leseGedaechtnis, liesFeld, loginAblauf, merkeSeite } from './login';
import { eigenerTab, fuelleFeld, FuellFehler, handyHinweis, leseSchluessel, protokoll, waehle, wertVon, type Was } from './fuellen';
import { einstellung } from './totp';
import { erlaubt, modellVon, stufenText } from './stufen';
import { fasseTempo, leseTempo } from './tempo';
import { sicherung, wiederherstellen } from './sicherung';
import { gewaehlt, nutzung, vorschlaege, wahlen, zeilen, type Wahl } from './tippen';

const HILFE = `heimherz einrichten
heimherz koppeln [NAME]
heimherz import bitwarden
heimherz import csv DATEI     (Apple Passwörter oder Chrome)
heimherz export bitwarden DATEI
heimherz liste [SUCHE]
heimherz weg ID|kasten:N [...]    (weich löschen nach Ahmeds Ja in der Notch, 30 Tage wiederherstellbar; kasten:2 = Zeile 2 im zuletzt gezeigten Lumen-Kästchen)
heimherz weg --zurueck ID [...]    (gelöschte Einträge wiederherstellen)
heimherz status
heimherz tempo [MINUTEN]    (Foto-Abgleich: wo hängt die Zeit, Standard 10)
heimherz geraet weg ID
heimherz sicherung    (verschlüsselte Tresor-Sicherung nach ~/Heimherz/Dateien/Sicherung und nach Drive; Timer: server/heimherz-sicherung.timer)
heimherz wiederherstellen DATEI   (Sicherung zusammenführen; auf neuem PC fragt es den Wiederherstellungscode von stdin)
heimherz fuell TAB CSS benutzer|passwort|code [--konto K] [--rahmen IFRAME-CSS] [--enter] [--auftrag DATEI]
heimherz login TAB --konto K [--code] [--auftrag DATEI]   (Benutzer, Passwort, Code, Absenden; Exit 0 eingeloggt, 8 falsches Passwort, 9 Code nötig, 10 Captcha, 11 unbekannt)
heimherz merke TAB CSS --konto K [--rahmen IFRAME-CSS] [--auftrag DATEI]   (Passwort aus dem Feld, das Ahmed per Handy-Karte gefüllt hat, in den Eintrag)
heimherz totp-setzen TAB --konto K [--feld CSS]   (Einrichtungsschlüssel der Seite in den Eintrag)
heimherz erlaubt HOST [--auftrag DATEI]   (Exit 0 erlaubt, 7 verweigert)
heimherz stufen
heimherz tippe [--id ID [--code|--nur-passwort] | --bereit]    (Taste Alt+Strg+P: Konto wählen, tippt Benutzer, Tab, Passwort oder Code ins aktive Fenster, jede App; --id ohne Auswahl, für Lumen-Vorschlag)
heimherz vorschlag    (Einträge ohne Werte als JSON, für Lumen-Vorschlag)`;

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

// Eine Zeile von stdin; am Terminal ohne Echo. Der Code geht nie über argv oder Umgebung.
async function liesCode(): Promise<string> {
  const tty = process.stdin.isTTY;
  if (tty) { process.stderr.write('Wiederherstellungscode (Eingabe bleibt unsichtbar): '); Bun.spawnSync(['stty', '-echo'], { stdin: 'inherit' }); }
  try {
    let text = '';
    for await (const teil of Bun.stdin.stream()) { text += Buffer.from(teil).toString(); if (text.includes('\n')) break; }
    return text.split('\n')[0].trim();
  } finally { if (tty) { Bun.spawnSync(['stty', 'echo'], { stdin: 'inherit' }); process.stderr.write('\n'); } }
}

async function lauf(argv: string[]): Promise<void> {
  const p = Bun.spawn(argv, { stdin: 'ignore', stdout: 'ignore', stderr: 'pipe' });
  const [fehler, rc] = await Promise.all([new Response(p.stderr).text(), p.exited]);
  if (rc !== 0) throw new Error(`${argv[0]} Exit ${rc}${fehler ? `: ${fehler.trim().split('\n').pop()?.slice(0, 200)}` : ''}`);
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
  if (cmd === 'weg' && r[0]) {
    if (r[0] === '--zurueck') { if (!(await eintragZurueck(a, r.slice(1)))) process.exitCode = 1; else a.ausgabe('wiederhergestellt'); return; }
    if (!(await eintragWeg(a, r.map(x => kastenId(x))))) process.exitCode = 1; else a.ausgabe('gelöscht (30 Tage wiederherstellbar)');
    return;
  }
  if (cmd === 'status') return status(a);
  if (cmd === 'tempo') { for (const z of fasseTempo(leseTempo(a.daten), Number(r[0]) > 0 ? Number(r[0]) : 10)) a.ausgabe(z); return; }
  if (cmd === 'sicherung') {
    const ok = await sicherung(a, {
      // nur .heimsicherung geht mit und wird auf Drive angefasst; --max-delete bremst, falls die Quelle je falsch wäre
      rclone: Bun.which('rclone') ? (q, z) => lauf(['rclone', 'sync', q, z, '--include', '*.heimsicherung', '--max-delete', '20']) : null,
      papierkorb: p => lauf(['trash-put', p]),
    });
    if (!ok) process.exitCode = 1;
    return;
  }
  if (cmd === 'wiederherstellen' && r[0]) return wiederherstellen(a, r[0], liesCode);
  if (cmd === 'geraet' && r[0] === 'weg' && r[1]) return geraetWeg(a, r[1]);
  if (cmd === 'tippe') { await tippe(a, r); if (r.includes('--bereit')) process.exit(process.exitCode ?? 0); return; }   // offener stdin-Leser und Zeitgeber halten sonst bis 60 s
  if (cmd === 'vorschlag') { a.ausgabe(JSON.stringify(vorschlaege(await eintraege(a), nutzungJetzt()))); return; }
  if (cmd === 'fuell' || cmd === 'login' || cmd === 'merke' || cmd === 'totp-setzen' || cmd === 'erlaubt' || cmd === 'stufen') return fuellen(a, cmd, r);
  console.error(HILFE);
  process.exitCode = 2;
}

// SPEC 23: Stufe prüfen, Eintrag wählen, Wert per CDP ins Feld; Protokoll ohne Werte, Stufe 1 meldet Ahmed am Handy.
async function fuellen(a: Abh, cmd: string, r: string[]) {
  const e = process.env, opt: Record<string, string | true> = {}, pos: string[] = [];
  for (let i = 0; i < r.length; i++) {
    if (r[i] === '--enter') opt.enter = true;
    else if (r[i] === '--code') opt.code = true;
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
  if (cmd === 'login' || cmd === 'merke') {
    if (!pos[0] || !opt.konto || (cmd === 'merke' && !pos[1])) { console.error(HILFE); process.exitCode = 2; return; }
    try {
      const t = eigenerTab(await ausgabeVon(['claude-chrome', 'tabs']), pos[0]);
      const host = new URL(t.url).hostname, port = Number(e.HEIMHERZ_CDP_PORT ?? 9333);
      const u = erlaubt(host, modell, auftrag, e);
      if (!u.ok) { protokoll(state, { host, was: cmd, stufe: u.stufe, modell, ok: false, grund: u.grund, auftrag }); throw new FuellFehler(`verweigert: ${u.grund}`, 7); }
      const it = waehle(await eintraege(a), t.url, cmd === 'login' ? 'passwort' : 'beliebig', opt.konto as string);
      const name = `${it.name} (${it.benutzer || host})`;
      if (u.stufe === 1) handyHinweis(e.XDG_RUNTIME_DIR ?? '', 'Sparkasse: Agent meldet sich an', `${modell}-Sitzung: ${cmd} auf ${host} (Auftrag ${auftrag?.split('/').pop()})`);
      if (cmd === 'merke') {
        let neu = await liesFeld({ port, tabId: t.id, css: pos[1], rahmen: opt.rahmen as string | undefined });
        try {
          if (neu === it.benutzer) throw new FuellFehler('Das Feld enthält den Benutzernamen, nicht das Passwort; nichts gespeichert');
          const n = neu.length, geschrieben = await passwortSetzen(a, it.id, neu);
          protokoll(state, { host, id: it.id, was: 'merke', stufe: u.stufe, modell, ok: true, grund: u.grund, auftrag });
          a.ausgabe(`gespeichert, ${n} Zeichen: ${name}${geschrieben ? '' : ' (war schon so)'}`);
        } finally { neu = ''; }
        return;
      }
      const mitCode = !!opt.code && !!einstellung(it.totp), merk = leseGedaechtnis(state);
      let r2 = await loginAblauf({ port, tabId: t.id, mitCode, bekannt: merk[host], wert: w => wertVon(it, w) });
      merkeSeite(state, host, r2);
      protokoll(state, { host, id: it.id, was: 'login', stufe: u.stufe, modell, ok: true, grund: `${u.grund}, ${r2.ergebnis}`, auftrag });
      a.ausgabe(`${r2.ergebnis}: ${name} in ${host} (${r2.hinweis})`);
      if (r2.ergebnis === 'falsches-passwort' && r2.passwortFeld) a.ausgabe(`Passwort neu: Karte mit handy_geheimnis auf Feld ${r2.passwortFeld}, dann heimherz merke ${pos[0]} ${r2.passwortFeld} --konto ${it.id.slice(0, 8)}`);
      process.exitCode = LOGIN_EXIT[r2.ergebnis];
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

async function ersteZeile(ms: number): Promise<string> {
  let text = '';
  const lesen = (async () => { for await (const t of Bun.stdin.stream()) { text += Buffer.from(t).toString(); if (text.includes('\n')) break; } return text.split('\n')[0]; })();
  return Promise.race([lesen, Bun.sleep(ms).then(() => '')]);
}

// kasten:N -> id der Zeile N im Lumen-Kästchen (der Dienst schreibt beim Zeigen $XDG_RUNTIME_DIR/lumen-vorschlag.json), höchstens 15 min alt.
function kastenId(x: string): string {
  const m = /^kasten:(\d+)$/.exec(x);
  if (!m) return x;
  const k = JSON.parse(readFileSync(join(process.env.XDG_RUNTIME_DIR ?? '', 'lumen-vorschlag.json'), 'utf8'));
  if (Date.now() / 1000 - k.zeit > 900) throw new Meldung('Das Lumen-Kästchen ist älter als 15 min, nichts gelöscht');
  const z = k.zeilen[Number(m[1]) - 1];
  if (!z) throw new Meldung(`Das Kästchen hatte keine Zeile ${m[1]}, nichts gelöscht`);
  return z.id;
}

const nutzungJetzt = () => { try { return nutzung(readFileSync(join(process.env.XDG_STATE_HOME ?? join(homedir(), '.local/state'), 'heimherz', 'fuell.log'), 'utf8')); } catch { return new Map<string, number>(); } };

// SPEC 29/30: nur Ahmeds Taste und Lumen-Vorschlag (Geheimnis-Wache sperrt `tippe` für Agenten). Fehler als Desktop-Meldung, es gibt kein Terminal.
async function tippe(a: Abh, r: string[]) {
  const melde = (t: string) => Bun.spawn(['notify-send', '-a', 'Lumen Cloud', 'Lumen Cloud', t], { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' });
  const schreibe = async (text: string) => {
    const p = Bun.spawn(['wtype', '-'], { stdin: 'pipe', stdout: 'ignore', stderr: 'ignore' });
    p.stdin!.write(text); await p.stdin!.end();
    if (await p.exited) throw new Error('wtype schlug fehl');
  };
  try {
    const f = JSON.parse(await ausgabeVon(['hyprctl', '-j', 'activewindow']));
    const w = wahlen(await eintraege(a), `${f.class ?? ''} ${f.title ?? ''}`, nutzungJetzt());
    if (!w.length) { melde('Keine Einträge mit Passwort'); return; }
    let id = r.includes('--id') ? r[r.indexOf('--id') + 1] : undefined, code = r.includes('--code'), nurPasswort = r.includes('--nur-passwort');
    if (r.includes('--bereit')) {   // Lumen-Vorschlag startet uns schon beim Zeigen des Kästchens: Tresor offen, der Klick schickt nur "ID [code|nur-passwort]"
      const z = (await ersteZeile(60_000)).trim().split(/\s+/);
      if (!z[0]) process.exit(0);   // Kästchen ohne Klick zu (EOF) oder Zeit um
      [id, code, nurPasswort] = [z[0], z.includes('code'), z.includes('nur-passwort')];
    }
    let x: Wahl | undefined;
    if (id) x = w.find(v => v.e.id === id && v.code === code);
    else {
      let antwort = '';
      try { antwort = await ausgabeVon(['fuzzel', '--dmenu', '--prompt', 'Lumen Cloud: ', '--width', '60'], undefined, zeilen(w)); } catch { return; }   // Esc
      x = gewaehlt(w, antwort);
      await Bun.sleep(150);   // fuzzel zu, Fokus zurück im Fenster
    }
    if (!x) return;
    if (x.code) await schreibe(await wertVon(x.e, 'code'));
    else {
      if (x.e.benutzer && !nurPasswort) { await schreibe(x.e.benutzer); await lauf(['wtype', '-k', 'Tab']); }
      await schreibe(x.e.passwort);
    }
    const state = join(process.env.XDG_STATE_HOME ?? join(homedir(), '.local/state'), 'heimherz');
    protokoll(state, { host: String(f.class ?? '?'), id: x.e.id, was: x.code ? 'tippe code' : 'tippe', stufe: 0, modell: 'ahmed', ok: true, grund: id ? 'Vorschlag' : 'Taste' });
  } catch (err: any) { melde(`Fehler: ${err?.message ?? err}`); process.exitCode = 1; }
}

main(process.argv.slice(2)).catch(err => {
  console.error(err instanceof Meldung ? err.message : `Fehler: ${err?.message ?? err}`);
  process.exit(1);
});
