// Stufen für Agenten-Füllen (SPEC 23): wer welchen Login füllen darf, nach Seite, Modell und Auftrag-Datei.
import { readFileSync, realpathSync, statSync } from 'node:fs';
import { join, sep } from 'node:path';

export type Modell = 'opus' | 'sonnet' | 'haiku' | 'unbekannt';
type Env = Record<string, string | undefined>;
export type Urteil = { ok: boolean; stufe: number; grund: string };

// Endungen (Seite oder Unterdomain davon). Ahmed 25.10.: Sparkasse zuerst, dann Kündigen, dann Amt.
const STUFEN: [number, string, string[]][] = [
  [1, 'Bank', ['spkvr.de', 'sparkasse.de', 'tink.com']],
  [2, 'Verträge, Versicherung, Gesundheit, Steuer', ['vodafone.de', 'telekom.de', 'o2online.de', '1und1.de', 'congstar.de', 'mark-e.de', 'eprimo.de', 'fitx.de', 'netflix.com', 'spotify.com', 'disneyplus.com', 'amazon.de', 'amazon.com', 'paypal.com', 'tk.de', 'aok.de', 'barmer.de', 'dak.de', 'huk.de', 'allianz.de', 'check24.de', 'elster.de']],
  [3, 'Amt', ['arbeitsagentur.de', 'jobcenter.digital', 'familienkasse.de', 'bund.de', 'service.nrw.de', 'hagen.de', 'ihk.de']],
  [4, 'Konten', ['google.com', 'apple.com', 'icloud.com', 'github.com', 'cloudflare.com', 'microsoft.com', 'live.com']],
];
// Mindest-Modell je Stufe; Stufe 1 braucht zusätzlich die Auftrag-Datei
const DARF: Record<number, Modell[]> = { 1: ['opus'], 2: ['opus'], 3: ['opus', 'sonnet'], 4: ['opus', 'sonnet'], 5: ['opus', 'sonnet', 'unbekannt'] };

export function stufeVon(host: string): number {
  const h = host.toLowerCase().replace(/\.$/, '');
  for (const [s, , endungen] of STUFEN) if (endungen.some(e => h === e || h.endsWith('.' + e))) return s;
  return 5;
}

export const stufenText = () => [...STUFEN.map(([s, name, e]) => `${s} ${name}: ${DARF[s].join(', ')}${s === 1 ? ' + Auftrag-Datei' : ''} | ${e.join(', ')}`), `5 Rest: ${DARF[5].join(', ')}`].join('\n');

// Unteragenten erben die Umgebung der Hauptsitzung (25.10. geprüft): sie zählen wie die Hauptsitzung.
export function modellVon(env: Env, cmdline: (pid: string) => string = pid => readFileSync(`/proc/${pid}/cmdline`, 'utf8')): Modell {
  let roh = '';
  try {
    if (env.CLAUDE_PID) {
      const a = cmdline(env.CLAUDE_PID).split('\0');
      const i = a.findIndex(x => x === '--model' || x.startsWith('--model='));
      if (i >= 0) roh = a[i].includes('=') ? a[i].split('=')[1] : a[i + 1] ?? '';
    }
  } catch { /* Prozess weg: wie unbekannt */ }
  roh ||= env.ANTHROPIC_MODEL ?? '';
  return /opus/i.test(roh) ? 'opus' : /sonnet/i.test(roh) ? 'sonnet' : /haiku/i.test(roh) ? 'haiku' : 'unbekannt';
}

const FREIGABE = (z: string) => /sparkasse/i.test(z) && /(meld\w* dich\b.*\ban|anmeld|einlogg|log dich ein|login)/i.test(z) && /(allein|selbe?r|selbst|nicht zu ?hause)/i.test(z);

export function auftragGilt(pfad: string, env: Env): { ok: boolean; grund: string } {
  const home = env.HOME ?? '';
  let echt: string;
  try { echt = realpathSync(pfad); } catch { return { ok: false, grund: 'Auftrag-Datei fehlt' }; }
  const orte = ['.claude/buero-stand', 'Documents/Obsidian/Personal', 'projects'].map(o => { try { return realpathSync(join(home, o)) + sep; } catch { return null; } }).filter(Boolean) as string[];
  if (!home || !orte.some(o => echt.startsWith(o))) return { ok: false, grund: 'Auftrag-Datei liegt nicht an einem erlaubten Ort (buero-stand, Vault, projects)' };
  if (Date.now() - statSync(echt).mtimeMs > 24 * 3600e3) return { ok: false, grund: 'Auftrag-Datei ist älter als 24 Stunden' };
  if (!readFileSync(echt, 'utf8').split('\n').some(FREIGABE)) return { ok: false, grund: 'Auftrag-Datei sagt nicht ausdrücklich: Sparkasse, anmelden, allein (oder nicht zuhause)' };
  return { ok: true, grund: echt };
}

export function erlaubt(host: string, modell: Modell, auftrag: string | undefined, env: Env): Urteil {
  const stufe = stufeVon(host);
  if (!DARF[stufe].includes(modell)) return { ok: false, stufe, grund: `Stufe ${stufe} (${host}) braucht ${DARF[stufe].join(' oder ')}, Sitzung ist ${modell}` };
  if (stufe === 1) {
    if (!auftrag) return { ok: false, stufe, grund: 'Sparkasse nur mit Auftrag-Datei (--auftrag oder HEIMHERZ_AUFTRAG), Ahmed 25.10.' };
    const a = auftragGilt(auftrag, env);
    if (!a.ok) return { ok: false, stufe, grund: a.grund };
  }
  return { ok: true, stufe, grund: `Stufe ${stufe}, ${modell}` };
}
