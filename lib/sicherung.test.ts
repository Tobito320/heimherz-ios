import { describe, expect, test } from 'bun:test';
import fx from '../fixtures/sicherung/wiederherstellung-1.json';
import { b64 } from './umschlag';
import { baueSicherung, behalten, codeAlsText, codeAusText, dateiName, entwickle, istBlatt, leseSicherung, umwickle } from './sicherung';

const umschlag = { v: 1 as const, rev: 7, nonce: 'oKGio6Slpqeoqaqr', daten: 'wvNbCY/YO3BdNJNH0+BJ6iOl0Xw=' };

describe('Wiederherstellungsblatt', () => {
  test('Testvektor: Code entpackt das Blatt zum Test-Schlüssel', async () => {
    const k = await entwickle(fx.blatt as any, codeAusText(fx.code));
    expect(Buffer.from(k).toString('base64')).toBe(fx.schluessel);
  });
  test('gleiche Eingabe gibt dasselbe Blatt (Swift muss es genauso bauen)', async () => {
    const code = codeAusText(fx.code), s = b64(fx.blatt.salt), n = b64(fx.blatt.nonce);
    expect(await umwickle(b64(fx.schluessel), code, s, n)).toEqual(fx.blatt as any);
  });
  test('falscher Code oder verändertes Blatt: Fehler ohne Inhalt', async () => {
    const falsch = codeAusText('AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA');
    await expect(entwickle(fx.blatt as any, falsch)).rejects.toThrow('Code passt nicht');
    await expect(entwickle({ ...fx.blatt, daten: fx.blatt.nonce + 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' } as any, codeAusText(fx.code))).rejects.toThrow();
  });
  test('Code: Text zu Bytes und zurück, Kleinschreibung und Leerzeichen erlaubt, Rest nicht', () => {
    const t = fx.code;
    expect(codeAlsText(codeAusText(t))).toBe(t);
    expect(codeAlsText(codeAusText(t.toLowerCase().replaceAll('-', ' ')))).toBe(t);
    expect(codeAusText(t)).toHaveLength(20);
    for (const schlecht of ['', 'ABCD', t + 'A', t.replace('K', '0'), t.replace('K', '1')]) expect(() => codeAusText(schlecht)).toThrow();
  });
  test('Zufallscode: 160 Bit, jedes Mal anders', () => {
    const a = crypto.getRandomValues(new Uint8Array(20)), b = crypto.getRandomValues(new Uint8Array(20));
    expect(codeAlsText(a)).not.toBe(codeAlsText(b));
    expect(codeAlsText(a)).toMatch(/^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$/);
  });
  test('istBlatt prüft Form streng', () => {
    expect(istBlatt(fx.blatt)).toBe(true);
    expect(istBlatt({ ...fx.blatt, salt: 'abc' })).toBe(false);
    expect(istBlatt({ ...fx.blatt, v: 2 })).toBe(false);
    expect(istBlatt(null)).toBe(false);
  });
});

describe('Sicherungsdatei', () => {
  test('bauen und lesen', () => {
    const s = baueSicherung(umschlag, fx.blatt as any, new Date('2026-10-26T10:00:00Z'));
    expect(s).toMatchObject({ heimsicherung: 1, rev: 7, datum: '2026-10-26T10:00:00.000Z' });
    expect(leseSicherung(JSON.stringify(s))).toEqual(s);
    expect('wiederherstellung' in baueSicherung(umschlag, null)).toBe(false);
  });
  test('Müll wird abgelehnt', () => {
    const s = baueSicherung(umschlag, null);
    for (const x of ['kein json', '{}', JSON.stringify({ ...s, rev: 8 }), JSON.stringify({ ...s, umschlag: { ...umschlag, nonce: 'x' } }), JSON.stringify({ ...s, wiederherstellung: { v: 1 } })]) expect(() => leseSicherung(x)).toThrow();
  });
});

describe('Aufbewahrung', () => {
  const tage = (n: number) => Array.from({ length: n }, (_, i) => dateiName(new Date(Date.UTC(2026, 9, 26) - i * 864e5).toISOString().slice(0, 10)));
  test('14 Tage plus je Monat die jüngste, nichts Fremdes', () => {
    const namen = [...tage(60), 'notizen.txt', 'heimherz-tresor-2026-10-26.heimsicherung.bak', dateiName('2026-05-03'), dateiName('2026-05-30')];
    const b = behalten(namen, '2026-10-26');
    for (const n of tage(14)) expect(b.has(n)).toBe(true);
    expect(b.has(dateiName('2026-10-12'))).toBe(false);      // 15. Tag zurück
    expect(b.has(dateiName('2026-09-30'))).toBe(true);        // jüngste im September
    expect(b.has(dateiName('2026-09-29'))).toBe(false);
    expect(b.has(dateiName('2026-08-31'))).toBe(true);        // jüngste im August
    expect(b.has(dateiName('2026-05-30'))).toBe(true);
    expect(b.has(dateiName('2026-05-03'))).toBe(false);
    expect(b.has('notizen.txt')).toBe(false);                 // fremde Namen sind nie "zu behalten", aber der Aufrufer löscht sie auch nie
  });
});
