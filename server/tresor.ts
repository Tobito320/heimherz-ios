// Tresor-Ablage (SPEC 6): ein Umschlag, rev vergibt der Server, alte Fassungen im Verlauf. Der Server sieht nie Klartext.
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { istUmschlag, type Umschlag } from '../lib/umschlag';
import { schreibeAtomar } from './geraete';
import { liesBegrenzt, json, TooLarge } from './http';

export const TRESOR_MAX = 20 * 1024 * 1024;

export class Tresor {
  private aktuellPfad: string;
  private verlauf: string;
  private kette: Promise<unknown> = Promise.resolve();

  constructor(daten: string, private verlaufMax = 200) {
    const dir = join(daten, 'tresor');
    this.aktuellPfad = join(dir, 'aktuell.json');
    this.verlauf = join(dir, 'verlauf');
    mkdirSync(this.verlauf, { recursive: true });
  }

  aktuell(): Umschlag | null {
    try { return JSON.parse(readFileSync(this.aktuellPfad, 'utf8')); } catch { return null; }
  }

  rev() { return this.aktuell()?.rev ?? 0; }

  holen(): Response {
    const u = this.aktuell();
    return u ? json(u) : new Response(null, { status: 404 });
  }

  // Schreibende Anfragen laufen nacheinander (Lesen, Vergleichen, Schreiben ist sonst nicht atomar).
  speichern(req: Request): Promise<Response> {
    const lauf = this.kette.then(() => this.speichereJetzt(req));
    this.kette = lauf.catch(() => {});
    return lauf;
  }

  private async speichereJetzt(req: Request): Promise<Response> {
    const m = (req.headers.get('if-match') ?? '').replace(/^W\//, '').replace(/"/g, '').trim();
    if (!/^\d+$/.test(m)) return new Response(null, { status: 428 });
    const alt = this.aktuell();
    if (Number(m) !== (alt?.rev ?? 0)) return alt ? json(alt, 409) : new Response(null, { status: 409 });

    let roh: Uint8Array;
    try { roh = await liesBegrenzt(req, TRESOR_MAX); } catch (e) {
      if (e instanceof TooLarge) return new Response(null, { status: 413 });
      throw e;
    }
    let neu: any;
    try { neu = JSON.parse(new TextDecoder().decode(roh)); } catch { return new Response(null, { status: 400 }); }
    if (!istUmschlag(neu)) return new Response(null, { status: 400 });

    // Erst alte Fassung sichern, dann ersetzen: bricht es dazwischen ab, bleibt der alte Stand gültig.
    if (alt) copyFileSync(this.aktuellPfad, join(this.verlauf, `${alt.rev}.json`));
    const gespeichert: Umschlag = { v: 1, rev: (alt?.rev ?? 0) + 1, nonce: neu.nonce, daten: neu.daten };
    schreibeAtomar(this.aktuellPfad, JSON.stringify(gespeichert));
    this.kuerzeVerlauf();
    return json(gespeichert);
  }

  private kuerzeVerlauf() {
    const revs = readdirSync(this.verlauf).map(f => /^(\d+)\.json$/.exec(f)?.[1]).filter((x): x is string => !!x).map(Number).sort((a, b) => b - a);
    for (const r of revs.slice(this.verlaufMax)) {
      const p = join(this.verlauf, `${r}.json`);
      if (existsSync(p)) unlinkSync(p);
    }
  }
}
