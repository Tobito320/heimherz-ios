import { afterAll, beforeAll, expect, test } from 'bun:test';
import { Database } from 'bun:sqlite';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Analyse, Entprellt, HAMMING_MAX, MIN_BITS, UNSCHARF_SCHWELLE, dhash, echteMerkmale, gesetzteBits, gruppiereAehnliche, hamming, lesePgm, schaerfe, waehleBehalten, type Grau, type Kandidat } from './analyse';
import { fotosAnalyse, fotosGruppen, fotosVorschlag, Meldung, type Abh } from '../bin/befehle';
import { baue } from './testhilfe';

const t = baue({ analyse: { entprellMs: 40, beiStart: false } });
const bilder = mkdtempSync(join(tmpdir(), 'heimherz-analyse-bilder-'));
const b = (n: string) => join(bilder, n);
const magick = (...a: string[]) => { const r = Bun.spawnSync(['magick', ...a]); expect(r.exitCode).toBe(0); };

afterAll(() => { t.ende(); rmSync(bilder, { recursive: true, force: true }); });

beforeAll(() => {
  // A: Rechteck und Kreis; E/E2: Dreieck und Balken (E2 ist E in doppelter Auflösung als JPEG); U: verwischt; S: scharf
  magick('-size', '300x200', 'xc:white', '-fill', 'black', '-draw', 'rectangle 20,20 120,150', '-fill', 'gray50', '-draw', 'circle 220,90 220,150', b('a.png'));
  magick('-size', '300x200', 'xc:white', '-fill', 'black', '-draw', 'polygon 10,190 150,10 290,190', '-fill', 'gray60', '-draw', 'rectangle 0,0 300,30', b('e.png'));
  magick(b('e.png'), '-resize', '200%', '-quality', '50', b('e2.jpg'));
  magick('-size', '640x480', 'xc:white', '-fill', 'black', '-draw', 'polygon 100,50 500,100 300,400', '-blur', '0x15', b('u.jpg'));
  magick(b('u.jpg'), b('u.png'));
  magick('-size', '640x480', 'xc:white', '-fill', 'black', '-draw', 'polygon 100,50 500,100 300,400', '-quality', '90', b('s.jpg'));
  writeFileSync(b('kaputt.jpg'), 'das ist kein Bild');
  for (const [n, quelle] of [['v1.mp4', 'testsrc=duration=2:size=320x240:rate=10'], ['v3.mp4', 'smptebars=duration=0.5:size=160x120:rate=10']]) {
    const r = Bun.spawnSync(['ffmpeg', '-loglevel', 'error', '-f', 'lavfi', '-i', quelle, b(n)]);
    expect(r.exitCode).toBe(0);
  }
});

// ---------- reine Rechnung ----------

const grau = (w: number, h: number, f: (x: number, y: number) => number): Grau => ({ w, h, daten: Uint8Array.from({ length: w * h }, (_, i) => f(i % w, Math.floor(i / w))) });

test('dHash: gleiches Bild gleich, Hamming zählt Bits, kleine Bilder gehen', () => {
  const links = grau(90, 80, x => 255 - x * 2);
  expect(dhash(links)).toBe(dhash(grau(90, 80, x => 255 - x * 2)));
  expect(gesetzteBits(dhash(links))).toBe(64);
  expect(dhash(grau(90, 80, x => x * 2))).toBe('0000000000000000');
  expect(hamming('0000000000000000', 'ffffffffffffffff')).toBe(64);
  expect(hamming('00000000000000ff', '0000000000000000')).toBe(8);
  expect(hamming('8000000000000001', '0000000000000000')).toBe(2);
  expect(dhash(grau(2, 2, x => x * 100))).toHaveLength(16);
});

test('Schärfe: Kante hoch, flach null', () => {
  expect(schaerfe(grau(64, 64, () => 100))).toBe(0);
  expect(schaerfe(grau(64, 64, x => (x >> 2) % 2 ? 255 : 0))).toBeGreaterThan(1000);
  expect(schaerfe(grau(2, 2, () => 5))).toBe(0);
});

test('Union-Find: Ketten werden eine Gruppe, Abstand über der Grenze nicht', () => {
  const h = (n: number) => '0'.repeat(16 - n.toString(16).length) + n.toString(16);
  // a-b Abstand 6, b-c Abstand 6, a-c Abstand 12: Kette, trotzdem eine Gruppe
  const a = h(0), b2 = h(0b111111), c = h(0b111111111111), fern = 'ffffffffffffffff';
  expect(HAMMING_MAX).toBe(6);
  const g = gruppiereAehnliche([{ id: 'a', dhash: a }, { id: 'b', dhash: b2 }, { id: 'c', dhash: c }, { id: 'z', dhash: fern }]);
  expect(g.map(x => x.sort())).toEqual([['a', 'b', 'c']]);
  expect(gruppiereAehnliche([{ id: 'a', dhash: a }, { id: 'c', dhash: c }])).toEqual([]);
});

const k = (kennung: string, o: Partial<Kandidat> = {}): Kandidat => ({ kennung, pixel: 1000, bearbeitet: false, schaerfe: 100, aufnahme: '2026-01-01', ...o });

test('Vorschlag: Auflösung, dann bearbeitet, dann schärfer, dann älter, dann Kennung', () => {
  expect(waehleBehalten([k('a'), k('b', { pixel: 2000 })])).toEqual({ behalten: 'b', grund: 'höchste Auflösung' });
  expect(waehleBehalten([k('a', { bearbeitet: true }), k('b', { schaerfe: 900 })])).toEqual({ behalten: 'a', grund: 'bearbeitet' });
  expect(waehleBehalten([k('a'), k('b', { schaerfe: 900 })])).toEqual({ behalten: 'b', grund: 'am schärfsten' });
  expect(waehleBehalten([k('a'), k('b', { schaerfe: 103 })]).grund).toBe('gleich gut, Kopie'); // unter 5 % Unterschied zählt nicht
  expect(waehleBehalten([k('a', { aufnahme: '2026-03-01' }), k('b', { aufnahme: '2026-02-01' })])).toEqual({ behalten: 'b', grund: 'ältestes' });
  expect(waehleBehalten([k('z'), k('m')])).toEqual({ behalten: 'm', grund: 'gleich gut, Kopie' });
  // Auflösung schlägt Schärfe
  expect(waehleBehalten([k('a', { pixel: 4000, schaerfe: 1 }), k('b', { schaerfe: 9999 })]).behalten).toBe('a');
});

test('PGM lesen: mit Kommentar, zu kurz wirft', () => {
  const kopf = new TextEncoder().encode('P5\n# x\n3 2\n255\n');
  const g = lesePgm(new Uint8Array([...kopf, 1, 2, 3, 4, 5, 6]));
  expect([g.w, g.h, [...g.daten]]).toEqual([3, 2, [1, 2, 3, 4, 5, 6]]);
  expect(() => lesePgm(new Uint8Array([...kopf, 1, 2]))).toThrow();
  expect(() => lesePgm(new TextEncoder().encode('P6\n1 1\n255\n\0\0\0'))).toThrow();
});

test('Entprellen: viele Auslöser ein Lauf; Auslöser im Lauf genau ein weiterer', async () => {
  let n = 0, tor: (() => void) | null = null;
  const e = new Entprellt(20, async () => { n++; if (n === 2) await new Promise<void>(r => (tor = r)); });
  e.ausloesen(); e.ausloesen(); e.ausloesen();
  await Bun.sleep(80);
  expect(n).toBe(1);
  e.ausloesen();
  await Bun.sleep(80);
  expect(n).toBe(2); // läuft noch, wartet am Tor
  e.ausloesen(); e.ausloesen(); // währenddessen
  await Bun.sleep(60);
  expect(n).toBe(2);
  tor!();
  await Bun.sleep(100);
  expect(n).toBe(3);
  await Bun.sleep(100);
  expect(n).toBe(3);
  const aus = new Entprellt(20, async () => { n++; });
  aus.ausloesen(); aus.stoppe();
  await Bun.sleep(60);
  expect(n).toBe(3);
});

// ---------- echte Programme ----------

test('echte Merkmale: scharf über, verwischt unter der Schwelle; Bilder gleicher Form liegen nah beieinander', async () => {
  const s = await echteMerkmale(b('s.jpg'), 'foto'), u = await echteMerkmale(b('u.jpg'), 'foto');
  expect(s.schaerfe!).toBeGreaterThan(UNSCHARF_SCHWELLE);
  expect(u.schaerfe!).toBeLessThan(UNSCHARF_SCHWELLE);
  expect([s.breite, s.hoehe]).toEqual([640, 480]);
  const e = await echteMerkmale(b('e.png'), 'foto'), e2 = await echteMerkmale(b('e2.jpg'), 'foto'), a = await echteMerkmale(b('a.png'), 'foto');
  expect(hamming(e.dhash!, e2.dhash!)).toBeLessThanOrEqual(HAMMING_MAX);
  expect(hamming(e.dhash!, a.dhash!)).toBeGreaterThan(HAMMING_MAX);
  for (const m of [e, e2, a, s, u]) expect(gesetzteBits(m.dhash!)).toBeGreaterThanOrEqual(MIN_BITS);
  expect([e2.breite, e2.hoehe]).toEqual([600, 400]);
  const kaputt = await echteMerkmale(b('kaputt.jpg'), 'foto');
  expect(kaputt.sha256).toHaveLength(64);
  expect([kaputt.dhash, kaputt.schaerfe, kaputt.breite]).toEqual([null, null, null]);
  const v = await echteMerkmale(b('v1.mp4'), 'video'), kurz = await echteMerkmale(b('v3.mp4'), 'video');
  expect([v.breite, v.hoehe]).toEqual([320, 240]);
  expect(v.dhash).toHaveLength(16);
  expect([kurz.breite, kurz.hoehe]).toEqual([160, 120]); // Video unter einer Sekunde: erstes Bild
  expect(kurz.dhash).toHaveLength(16);
});

// ---------- Dienst: Routen ----------

const auf = (kennung: string, ressource: string, datei: string, aufnahme: string, name = datei.split('/').pop()!) =>
  t.f(`/v1/fotos/${kennung}/${ressource}`, { method: 'PUT', headers: { 'x-aufnahme': aufnahme, 'x-dateiname': name }, body: readFileSync(datei) });
const analyse = async () => (await (await t.f('/v1/fotos/analyse')).json()) as any;
const warteBis = async (f: () => Promise<boolean>) => { for (let i = 0; i < 300; i++) { if (await f()) return; await Bun.sleep(100); } throw new Error('Zeit um'); };

test('beide Routen: ohne Token 401, falsche Methode 404', async () => {
  expect((await t.ohne('/v1/fotos/analyse')).status).toBe(401);
  expect((await t.ohne('/v1/fotos/papierkorb', { method: 'POST', body: '{}' })).status).toBe(401);
  expect((await t.f('/v1/fotos/papierkorb')).status).toBe(404);
  expect((await t.f('/v1/fotos/analyse', { method: 'POST' })).status).toBe(404);
});

test('leere Analyse: nichts gerechnet, kein Stand, keine Gruppen', async () => {
  expect(await analyse()).toEqual({ stand: null, gerechnet: 0, offen: 0, gruppen: [], unscharf: [], groesste: [] });
});

test('Uploads lösen die Analyse von selbst aus (entprellt); Gleiche, Ähnliche, Unscharfe, Größte', async () => {
  const d = '2026-05-0';
  for (const [kennung, datei, tag] of [['KA1', 'a.png', 1], ['KA2', 'a.png', 2], ['KE1', 'e.png', 3], ['KE2', 'e2.jpg', 4], ['KU1', 'u.jpg', 5], ['KU2', 'u.png', 6], ['KS1', 's.jpg', 7], ['KK1', 'kaputt.jpg', 8]] as const)
    expect((await auf(kennung, 'foto-0', b(datei), `${d}${tag}T10:00:00`)).status).toBe(200);
  expect((await auf('KV1', 'video-0', b('v1.mp4'), '2026-05-09T10:00:00')).status).toBe(200);
  expect((await auf('KV2', 'video-0', b('v1.mp4'), '2026-05-10T10:00:00')).status).toBe(200);
  expect((await auf('KV3', 'video-0', b('v3.mp4'), '2026-05-11T10:00:00')).status).toBe(200);
  // Live Photo: Foto plus Videoteil; der Videoteil zählt nur zur Größe
  expect((await auf('KL1', 'foto-0', b('s.jpg'), '2026-05-12T10:00:00')).status).toBe(200);
  expect((await auf('KL1', 'live-0', b('v1.mp4'), '2026-05-12T10:00:00', 'live.mov')).status).toBe(200);
  await warteBis(async () => { const x = await analyse(); return x.stand !== null && x.offen === 0 && x.gerechnet === 12; });
  const x = await analyse();
  const gleich = x.gruppen.filter((g: any) => g.art === 'gleich').map((g: any) => [...g.kennungen].sort());
  expect(gleich.sort()).toEqual([['KA1', 'KA2'], ['KV1', 'KV2'], ['KL1', 'KS1']].sort());
  const aehnlich = x.gruppen.filter((g: any) => g.art === 'aehnlich');
  const e = aehnlich.find((g: any) => g.kennungen.includes('KE1'));
  expect(e).toEqual({ art: 'aehnlich', kennungen: ['KE2', 'KE1'], behalten: 'KE2', grund: 'höchste Auflösung' });
  for (const g of x.gruppen.filter((g: any) => g.art === 'gleich')) expect(g.kennungen[0]).toBe(g.behalten);
  // Gleiche stehen nicht zusätzlich in Ähnliche
  const inGleich = new Set(gleich.flat());
  for (const g of aehnlich) for (const kk of g.kennungen) expect(inGleich.has(kk)).toBe(false);
  // Unscharf: das verwischte JPEG, nicht das PNG (Screenshot), nicht das scharfe, nicht das kaputte
  expect(x.unscharf).toEqual(['KU1']);
  expect(x.groesste[0].bytes).toBeGreaterThanOrEqual(x.groesste[1].bytes);
  const kl = x.groesste.find((g: any) => g.kennung === 'KL1');
  expect(kl.bytes).toBe(readFileSync(b('s.jpg')).length + readFileSync(b('v1.mp4')).length);
  // kaputtes Bild: Zeile da (sonst bliebe offen über 0), ohne Hash
  const db = new Database(join(t.daten, 'fotos.db'), { readonly: true });
  expect(db.query("SELECT sha256 IS NOT NULL AS s, dhash FROM analyse WHERE kennung = 'KK1'").get()).toEqual({ s: 1, dhash: null });
  expect(db.query("SELECT COUNT(*) AS n FROM analyse WHERE ressource = 'live-0'").get()).toEqual({ n: 0 });
  db.close();
});

test('zweiter Lauf rechnet nichts neu; geänderte Größe wird neu gerechnet', async () => {
  const an = new Analyse(t.daten, t.fotos);
  expect((await an.rechne()).gerechnet).toBe(0);
  const db = new Database(join(t.daten, 'fotos.db'));
  db.run("UPDATE fotos SET groesse = groesse + 1 WHERE kennung = 'KE1' AND ressource = 'foto-0'");
  expect((await an.rechne()).gerechnet).toBe(1);
  expect((await an.rechne()).gerechnet).toBe(0);
  db.close(); an.schliesse();
});

test('fehlt die Datei, wird die Zeile nicht erfunden und bleibt offen', async () => {
  const an = new Analyse(t.daten, t.fotos);
  const db = new Database(join(t.daten, 'fotos.db'));
  db.run("INSERT INTO fotos (kennung, ressource, groesse, pfad, empfangen) VALUES ('KW1', 'foto-0', 5, ?, '2026-05-20T00:00:00Z')", [join(t.fotos, '2026/05/gibtsnicht.jpg')]);
  const r = await an.rechne();
  expect([r.gerechnet, r.fehlt, r.offen]).toEqual([0, 1, 1]);
  db.run("DELETE FROM fotos WHERE kennung = 'KW1'");
  db.close(); an.schliesse();
});

test('Vorschlag ändern (CLI-Weg): nur ein Mitglied der Gruppe, Text bereinigt, wirkt in der Antwort', async () => {
  const an = new Analyse(t.daten, t.fotos);
  expect(an.setzeVorschlag('KE1', 'KA1', 'x')).toBe(false); // nicht in der Gruppe
  expect(an.setzeVorschlag('NIE', 'NIE', 'x')).toBe(false);
  expect(an.setzeVorschlag('KE2', 'KE1', 'Das Dreieck\n  ist schöner\u0000')).toBe(true); // irgendein Mitglied nennt die Gruppe
  an.schliesse();
  const g = (await analyse()).gruppen.find((x: any) => x.kennungen.includes('KE1'));
  expect([g.behalten, g.kennungen[0], g.grund]).toEqual(['KE1', 'KE1', 'Das Dreieck   ist schöner']);
});

const abh = (zeilen: string[]): Abh => ({ daten: t.daten, fotos: t.fotos, dateien: '', dienstUrl: '', creds: {} as any, ausgabe: z => zeilen.push(z) });

test('CLI: analyse mit den Zahlen im Format aus SPEC 25, gruppen mit relativen Pfaden, vorschlag', async () => {
  const z: string[] = [];
  await fotosAnalyse(abh(z));
  expect(z[0]).toMatch(/^\d+ Assets, 3 Gruppen gleich \(6 Fotos\), 2 ähnlich, 1 unscharf$/);
  expect(z[1]).toMatch(/neu gerechnet: 0 in [\d.]+ s/);
  const j: string[] = [];
  await fotosGruppen(abh(j), true);
  const gruppen = JSON.parse(j[0]);
  expect(gruppen.length).toBe(5);
  for (const g of gruppen) for (const f of g.assets) {
    expect(f.pfad.startsWith('/')).toBe(false);
    expect(existsSync(join(t.fotos, f.pfad))).toBe(true);
    expect(f.bytes).toBeGreaterThan(0);
  }
  const text: string[] = [];
  await fotosGruppen(abh(text), false);
  expect(text.filter(l => !l.startsWith(' ')).every(l => /^(gleich|aehnlich)\tbehalten=\S+\t.+/.test(l))).toBe(true);
  const v: string[] = [];
  await fotosVorschlag(abh(v), 'KE2', 'KE2', 'doch die Große');
  expect(v[0]).toContain('KE2');
  expect((await analyse()).gruppen.find((x: any) => x.kennungen.includes('KE1')).behalten).toBe('KE2');
  await expect(fotosVorschlag(abh([]), 'KE1', 'KA1', 'x')).rejects.toBeInstanceOf(Meldung);
});

// ---------- Papierkorb ----------

const korb = (kennungen: unknown) => t.f('/v1/fotos/papierkorb', { method: 'POST', body: JSON.stringify({ kennungen }) });
const dateienOrdner = (dir: string): string[] => existsSync(dir) ? readdirSync(dir, { recursive: true }).map(String) : [];

test('Papierkorb: schlechte Bodys 400', async () => {
  expect((await t.f('/v1/fotos/papierkorb', { method: 'POST', body: 'kein json' })).status).toBe(400);
  expect((await korb('K1')).status).toBe(400);
  expect((await korb([1])).status).toBe(400);
});

test('Papierkorb: alle Dateien des Assets gehen in den Papierkorb, Zeilen nach geloescht, unbekannte zählen nicht', async () => {
  const vorher = ((await (await t.f('/v1/fotos/bekannt')).json()) as any[]).length;
  const r = await korb(['KL1', 'KL1', 'GIBTS-NICHT', 'KK1']);
  expect(r.status).toBe(200);
  expect(await r.json()).toEqual({ verschoben: 2, fehler: 0 });
  const bekannt = (await (await t.f('/v1/fotos/bekannt')).json()) as any[];
  expect(bekannt.length).toBe(vorher - 3); // KL1 hat zwei Ressourcen, KK1 eine
  expect(bekannt.some(x => x.kennung === 'KL1' || x.kennung === 'KK1')).toBe(false);
  expect(dateienOrdner(t.korb).length).toBe(3);
  const db = new Database(join(t.daten, 'fotos.db'), { readonly: true });
  expect(db.query("SELECT COUNT(*) AS n FROM geloescht WHERE kennung IN ('KL1','KK1')").get()).toEqual({ n: 3 });
  expect(db.query("SELECT COUNT(*) AS n FROM analyse WHERE kennung IN ('KL1','KK1')").get()).toEqual({ n: 0 });
  db.close();
  const x = await analyse();
  expect(x.groesste.some((g: any) => g.kennung === 'KL1')).toBe(false);
  expect(x.gruppen.some((g: any) => g.kennungen.includes('KL1'))).toBe(false);
  expect(await (await korb(['KL1'])).json()).toEqual({ verschoben: 0, fehler: 0 }); // zweites Mal nichts mehr
});

test('Papierkorb: ein Vorschlag für ein verschobenes Asset verschwindet; schon fehlende Datei wandert trotzdem', async () => {
  const db = new Database(join(t.daten, 'fotos.db'));
  const pfad = (db.query("SELECT pfad FROM fotos WHERE kennung = 'KS1'").get() as any).pfad as string;
  rmSync(pfad); // Datei ist schon weg (z. B. von Hand gelöscht)
  expect(await (await korb(['KS1'])).json()).toEqual({ verschoben: 1, fehler: 0 });
  expect(db.query("SELECT COUNT(*) AS n FROM fotos WHERE kennung = 'KS1'").get()).toEqual({ n: 0 });
  db.close();
});

test('Papierkorb: Zeile mit Pfad außerhalb des Fotos-Ordners wird nie angefasst', async () => {
  const draussen = join(t.wurzel, 'draussen.txt');
  writeFileSync(draussen, 'GEHEIM');
  const db = new Database(join(t.daten, 'fotos.db'));
  db.run("INSERT INTO fotos (kennung, ressource, groesse, pfad, empfangen) VALUES ('KX1', 'foto-0', 6, ?, '2026-05-21T00:00:00Z')", [draussen]);
  db.run("INSERT INTO fotos (kennung, ressource, groesse, pfad, empfangen) VALUES ('KX2', 'foto-0', 6, ?, '2026-05-21T00:00:00Z')", [join(t.fotos, '..', 'draussen.txt')]);
  expect(await (await korb(['KX1', 'KX2'])).json()).toEqual({ verschoben: 0, fehler: 2 });
  expect(readFileSync(draussen, 'utf8')).toBe('GEHEIM');
  expect(db.query("SELECT COUNT(*) AS n FROM fotos WHERE kennung IN ('KX1','KX2')").get()).toEqual({ n: 2 });
  db.run("DELETE FROM fotos WHERE kennung IN ('KX1','KX2')");
  db.close();
});

test('Papierkorb: scheitert der Befehl, bleibt alles wie es war (nie rm)', async () => {
  const f = baue({ papierkorb: ['/usr/bin/false'], analyse: { beiStart: false } });
  try {
    const r = await f.f('/v1/fotos/K9/foto-0', { method: 'PUT', headers: { 'x-dateiname': 'x.jpg' }, body: readFileSync(b('a.png')) });
    expect(r.status).toBe(200);
    const antwort = await (await f.f('/v1/fotos/papierkorb', { method: 'POST', body: JSON.stringify({ kennungen: ['K9'] }) })).json();
    expect(antwort).toEqual({ verschoben: 0, fehler: 1 });
    expect(((await (await f.f('/v1/fotos/bekannt')).json()) as any[]).length).toBe(1);
    expect(dateienOrdner(f.fotos).filter(n => n.endsWith('x.jpg')).length).toBe(1);
  } finally { f.ende(); }
});

test('Papierkorb nutzt nur den eingestellten Befehl, kein rm im Quelltext', () => {
  const quelle = readFileSync(join(import.meta.dir, 'analyse.ts'), 'utf8');
  expect(quelle).not.toMatch(/\brm(Sync)?\(|unlink|\['rm'/);
});
