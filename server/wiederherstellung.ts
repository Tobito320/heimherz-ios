// Wiederherstellungsblatt (SPEC 25, W-036): der mit dem Handy-Code umwickelte Tresorschlüssel. Der Dienst prüft nur die Form und sieht weder Code noch K.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { istBlatt } from '../lib/sicherung';
import { schreibeAtomar } from './geraete';
import { json, leer, liesBegrenzt, TooLarge } from './http';

export class Wiederherstellung {
  private pfad: string;
  constructor(daten: string) { this.pfad = join(daten, 'wiederherstellung.json'); }

  blatt(): unknown | null {
    try { const b = JSON.parse(readFileSync(this.pfad, 'utf8')); return istBlatt(b) ? b : null; } catch { return null; }
  }

  holen(): Response {
    const b = this.blatt();
    return b ? json(b) : leer(404);
  }

  // Nur das Handy schreibt, ein neuer Code ersetzt den alten (letzter gewinnt).
  async speichern(req: Request): Promise<Response> {
    let roh: Uint8Array;
    try { roh = await liesBegrenzt(req, 4096); } catch (e) { if (e instanceof TooLarge) return leer(413); throw e; }
    let b: unknown;
    try { b = JSON.parse(new TextDecoder().decode(roh)); } catch { return leer(400); }
    if (!istBlatt(b)) return leer(400);
    const sauber = { v: 1, salt: b.salt, nonce: b.nonce, daten: b.daten };
    schreibeAtomar(this.pfad, JSON.stringify(sauber));
    return json(sauber);
  }
}
