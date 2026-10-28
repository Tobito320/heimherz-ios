// Läuft in der Seite (MAIN): Chromes Fenster "Passkey von einem anderen Gerät" kommt nicht mehr. Stille Abfragen bleiben offen,
// sichtbare werden wie "Abbrechen" abgelehnt, damit die Seite auf Passwort umschaltet (SPEC 28). Passkeys anlegen bleibt unberührt.
(() => {
  const c = navigator.credentials;
  if (!c?.get) return;
  const echt = c.get.bind(c);
  c.get = function (o) {
    if (!o?.publicKey) return echt(o);
    if (o.mediation === 'conditional') return new Promise((_, nein) => o.signal?.addEventListener('abort', () => nein(o.signal.reason ?? new DOMException('Abgebrochen', 'AbortError'))));
    return Promise.reject(new DOMException('The operation either timed out or was not allowed.', 'NotAllowedError'));
  };
})();
