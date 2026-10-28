import { expect, test } from 'bun:test';
import type { Eintrag } from '../lib/zusammenfuehren';
import { antwort, ERWEITERUNG_ID, liesNachricht, packe, vonAhmedsChrome } from './browser';

const e = (x: Partial<Eintrag>): Eintrag => ({ id: 'id', art: 'login', name: 'x', benutzer: 'tobi@beispiel.de', passwort: 'erfunden-1', urls: [], totp: '', notiz: '', favorit: false, geaendert: '2026-10-01T00:00:00Z', geloescht: false, ...x });
const l = [
  e({ id: 'aaa', name: 'Amt', urls: ['https://sso.beispiel-amt.de/login'], totp: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }),
  e({ id: 'bbb', urls: ['https://beispiel-amt.de.boese.example/'] }),
  e({ id: 'ccc', urls: ['https://web.beispiel-amt.de/'], geloescht: true }),
];

test('liste: nur passende Seite, ohne Geheimnisse', async () => {
  const r: any = await antwort({ typ: 'liste', url: 'https://web.beispiel-amt.de/post' }, l);
  expect(r.eintraege).toEqual([{ id: 'aaa', name: 'Amt', benutzer: 'tobi@beispiel.de', passwort: true, code: true }]);
  expect(JSON.stringify(r)).not.toContain('erfunden-1');
  expect((await antwort({ typ: 'liste', url: 'http://web.beispiel-amt.de/' }, l) as any).eintraege).toEqual([]);   // kein http
});

test('wert: Seite wird neu geprüft, fremde Seite bekommt nichts', async () => {
  expect(await antwort({ typ: 'wert', url: 'https://sso.beispiel-amt.de/', id: 'aaa', was: 'passwort' }, l)).toEqual({ wert: 'erfunden-1' });
  expect(await antwort({ typ: 'wert', url: 'https://boese.example/', id: 'aaa', was: 'passwort' }, l)).toHaveProperty('fehler');
  expect(await antwort({ typ: 'wert', url: 'https://web.beispiel-amt.de/', id: 'ccc', was: 'passwort' }, l)).toHaveProperty('fehler');
  expect(((await antwort({ typ: 'wert', url: 'https://sso.beispiel-amt.de/', id: 'aaa', was: 'code' }, l, () => 59_000)) as any).wert).toBe('287082');
  expect(await antwort({ typ: 'wert', url: 'https://sso.beispiel-amt.de/', id: 'aaa', was: 'notiz' as any }, l)).toHaveProperty('fehler');
});

test('Rahmen: hin und zurück, zu groß abgelehnt', () => {
  expect(liesNachricht(packe({ a: 'ä' }))).toEqual({ a: 'ä' });
  const b = Buffer.alloc(8); b.writeUInt32LE(1e6);
  expect(() => liesNachricht(b)).toThrow();
});

test('nur Ahmeds Chrome', () => {
  const o = `chrome-extension://${ERWEITERUNG_ID}/`;
  expect(vonAhmedsChrome([o], '/opt/google/chrome/chrome\0https://x.de/\0')).toBeNull();
  expect(vonAhmedsChrome(['chrome-extension://andere/'], '/opt/google/chrome/chrome\0')).not.toBeNull();
  expect(vonAhmedsChrome([o], '/opt/google/chrome/chrome\0--user-data-dir=/home/tobi/.cache/claude-browser-amt\0--remote-debugging-port=9333\0')).not.toBeNull();
  expect(vonAhmedsChrome([o], '/usr/bin/bash\0')).not.toBeNull();
});
