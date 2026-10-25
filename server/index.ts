import { homedir } from 'node:os';
import { join } from 'node:path';
import { starte } from './dienst';

const e = process.env;
const server = starte({
  port: Number(e.HEIMHERZ_PORT ?? 8790),
  daten: e.HEIMHERZ_DATEN ?? join(homedir(), '.local/share/heimherz'),
  fotos: e.HEIMHERZ_FOTOS ?? join(homedir(), 'Heimherz/Fotos'),
  dateien: e.HEIMHERZ_DATEIEN ?? join(homedir(), 'Heimherz/Dateien'),
});
console.error(`Heimherz läuft auf http://${server.hostname}:${server.port}`);
