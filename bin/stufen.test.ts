import { afterAll, expect, test } from 'bun:test';
import { mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { auftragGilt, erlaubt, modellVon, stufeVon } from './stufen';

const heim = mkdtempSync(join(tmpdir(), 'heimherz-stufen-'));
afterAll(() => rmSync(heim, { recursive: true, force: true }));
const stand = join(heim, '.claude/buero-stand');
mkdirSync(stand, { recursive: true });
const datei = (name: string, text: string, ort = stand) => { const p = join(ort, name); writeFileSync(p, text); return p; };
const FREIGABE = 'Ahmed: "geh in sparkasse melde dich an und lies die Umsätze, ich bin nicht zuhause, mach alles alleine"';

test('Stufe je Seite, Unterdomain zählt, Fremdes ist 5', () => {
  expect(stufeVon('www.spkvr.de')).toBe(1);
  expect(stufeVon('banking.sparkasse.de')).toBe(1);
  expect(stufeVon('link.tink.com')).toBe(1);
  expect(stufeVon('selfservice.mark-e.de')).toBe(2);
  expect(stufeVon('www.vodafone.de')).toBe(2);
  expect(stufeVon('sso.arbeitsagentur.de')).toBe(3);
  expect(stufeVon('accounts.google.com')).toBe(4);
  expect(stufeVon('spkvr.de.boese.example')).toBe(5);   // nur echte Endung zählt
  expect(stufeVon('nichtspkvr.de')).toBe(5);
  expect(stufeVon('example.com')).toBe(5);
});

test('Modell aus der Befehlszeile der Claude-Sitzung', () => {
  const cmd = (s: string) => () => s.split(' ').join('\0');
  expect(modellVon({ CLAUDE_PID: '1' }, cmd('claude --model claude-opus-5-5 --effort medium'))).toBe('opus');
  expect(modellVon({ CLAUDE_PID: '1' }, cmd('claude --model=claude-sonnet-5-5'))).toBe('sonnet');
  expect(modellVon({ CLAUDE_PID: '1' }, cmd('claude -n x'))).toBe('unbekannt');
  expect(modellVon({ ANTHROPIC_MODEL: 'claude-haiku-5-5' }, () => { throw new Error('kein pid'); })).toBe('haiku');
  expect(modellVon({}, () => '')).toBe('unbekannt');
});

test('Auftrag-Datei: Ort, Alter und ausdrückliche Freigabe', () => {
  const env = { HOME: heim };
  expect(auftragGilt(datei('gut.md', `# Auftrag\n${FREIGABE}\n`), env).ok).toBe(true);
  expect(auftragGilt(datei('ohne-allein.md', 'Sparkasse: melde dich an und lies die Umsätze'), env).ok).toBe(true);   // Ahmed 27.10.: lesen reicht
  expect(auftragGilt(datei('lesen.md', 'Ahmed: "sparkasse lesen"'), env).ok).toBe(true);
  expect(auftragGilt(datei('ohne-lesen.md', 'Sparkasse: melde dich an'), env).ok).toBe(false);
  expect(auftragGilt(datei('selber.md', 'Sparkasse prüft. Und ich helfe bei der Anmeldung. Nur wenn es nötig ist. Er soll alles selber machen.'), env).ok).toBe(true);   // Ahmed 25.10.
  expect(auftragGilt(datei('andere-zeilen.md', 'Sparkasse prüfen\nich bin nicht zuhause, mach alles alleine\nmelde dich an'), env).ok).toBe(false);   // alles in einer Zeile
  const alt = datei('alt.md', FREIGABE); const t = Date.now() / 1000 - 25 * 3600; utimesSync(alt, t, t);
  expect(auftragGilt(alt, env).grund).toContain('älter');
  const fremd = mkdtempSync(join(tmpdir(), 'fremd-'));
  expect(auftragGilt(datei('x.md', FREIGABE, fremd), env).grund).toContain('Ort');
  rmSync(fremd, { recursive: true, force: true });
  expect(auftragGilt(join(stand, 'fehlt.md'), env).ok).toBe(false);
  expect(auftragGilt(join(stand, '..', '..', '..', 'etc', 'passwd'), env).ok).toBe(false);
});

test('Wer darf welche Stufe', () => {
  const env = { HOME: heim };
  const gut = datei('gut2.md', FREIGABE);
  expect(erlaubt('www.spkvr.de', 'opus', undefined, env).ok).toBe(false);
  expect(erlaubt('www.spkvr.de', 'sonnet', gut, env).ok).toBe(false);
  expect(erlaubt('www.spkvr.de', 'opus', gut, env).ok).toBe(true);
  expect(erlaubt('www.vodafone.de', 'sonnet', undefined, env).ok).toBe(false);
  expect(erlaubt('www.vodafone.de', 'opus', undefined, env).ok).toBe(true);
  expect(erlaubt('sso.arbeitsagentur.de', 'sonnet', undefined, env).ok).toBe(true);
  expect(erlaubt('sso.arbeitsagentur.de', 'unbekannt', undefined, env).ok).toBe(false);
  expect(erlaubt('github.com', 'sonnet', undefined, env).ok).toBe(true);
  expect(erlaubt('example.com', 'unbekannt', undefined, env).ok).toBe(true);
  expect(erlaubt('example.com', 'haiku', undefined, env).ok).toBe(false);
});
