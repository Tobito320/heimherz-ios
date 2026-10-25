// CLI `heimherz` (SPEC 7). Hier nur die echte Verdrahtung (Umgebung, systemd-creds, bw, qrencode); die Logik steht in befehle.ts.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { Meldung, einrichtenBefehl, exportBitwarden, geraetWeg, importBitwarden, koppelnBefehl, liste, status, type Abh } from './befehle';
import { urlAusTailscale } from './koppeln';
import { systemdCreds } from './schluessel';

const HILFE = `heimherz einrichten
heimherz koppeln [NAME]
heimherz import bitwarden
heimherz export bitwarden DATEI
heimherz liste [SUCHE]
heimherz status
heimherz geraet weg ID`;

async function ausgabeVon(argv: string[], env?: Record<string, string | undefined>, stdin?: string): Promise<string> {
  const p = Bun.spawn(argv, { stdin: stdin === undefined ? 'ignore' : 'pipe', stdout: 'pipe', stderr: 'ignore', env: env ?? process.env });
  if (stdin !== undefined) { p.stdin!.write(stdin); await p.stdin!.end(); }
  const [aus, rc] = await Promise.all([new Response(p.stdout).text(), p.exited]);
  if (rc !== 0) throw new Error(`${argv[0]} schlug fehl (${rc})`);
  return aus;
}

// Bitwarden-Sitzung von claude-bw; fehlt sie oder ist sie abgelaufen, ist der Tresor gesperrt. Ausgabe nur in den Speicher.
async function bwJson(): Promise<string> {
  const sitzung = join(process.env.XDG_RUNTIME_DIR ?? '', 'claude-bw/session');
  const gesperrt = new Meldung('Bitwarden gesperrt: claude-bw entsperre');
  if (!existsSync(sitzung)) throw gesperrt;
  const env = { ...process.env, BITWARDENCLI_APPDATA_DIR: join(homedir(), '.config/claude-bw'), BW_SESSION: readFileSync(sitzung, 'utf8').trim() };
  try { return await ausgabeVon(['bw', 'list', 'items', '--raw', '--nointeraction'], env); } catch { throw gesperrt; }
}

async function anzeigen(datei: string) {
  const cmd = Bun.which('claude-start') ? ['claude-start', '--fuer-ahmed', 'imv', datei] : ['xdg-open', datei];
  Bun.spawn(cmd, { stdin: 'ignore', stdout: 'ignore', stderr: 'ignore' }).unref();
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
  if (cmd === 'export' && r[0] === 'bitwarden' && r[1]) return exportBitwarden(a, r[1]);
  if (cmd === 'liste') return liste(a, r[0]);
  if (cmd === 'status') return status(a);
  if (cmd === 'geraet' && r[0] === 'weg' && r[1]) return geraetWeg(a, r[1]);
  console.error(HILFE);
  process.exitCode = 2;
}

main(process.argv.slice(2)).catch(err => {
  console.error(err instanceof Meldung ? err.message : `Fehler: ${err?.message ?? err}`);
  process.exit(1);
});
