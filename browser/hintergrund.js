// Leitet Anfragen der Seite an den Host (heimherz) weiter, über eine offene Verbindung (schnell). Die Seiten-URL kommt von Chrome (sender), nie von der Seite selbst.
let port = null, nr = 0;
const offen = new Map(), listen = new Map(), gewaehlt = new Map();   // listen: Ursprung -> {zeit, antwort}, ohne Geheimnisse; gewaehlt: Tab -> gewähltes Konto
const seite = u => new URL(u).hostname.replace(/^www\./, '').split('.').slice(-2).join('.');

function verbindung() {
  if (port) return port;
  port = chrome.runtime.connectNative('com.lumen.cloud');
  port.onMessage.addListener(m => { const f = offen.get(m.nr); offen.delete(m.nr); f?.(m); });
  port.onDisconnect.addListener(() => {
    const grund = chrome.runtime.lastError?.message || 'Lumen Cloud getrennt';
    port = null;
    for (const f of offen.values()) f({ fehler: grund });
    offen.clear();
  });
  return port;
}

const host = anfrage => new Promise(r => {
  const n = ++nr;
  const uhr = setTimeout(() => { offen.delete(n); r({ fehler: 'Lumen Cloud antwortet nicht' }); }, 15000);
  offen.set(n, x => { clearTimeout(uhr); r(x); });
  try { verbindung().postMessage({ nr: n, ...anfrage }); } catch (e) { offen.delete(n); clearTimeout(uhr); r({ fehler: String(e.message) }); }
});

chrome.runtime.onMessage.addListener((m, sender, antworte) => {
  const url = sender.url || '';
  if (!sender.tab || !/^https:\/\//.test(url)) { antworte({ fehler: 'Nur https-Seiten' }); return; }
  if (m.typ === 'liste') {
    const u = new URL(url).origin, c = listen.get(u);
    if (c && Date.now() - c.zeit < 120000) { antworte(c.antwort); return; }
    host({ typ: 'liste', url }).then(a => { if (!a.fehler) listen.set(u, { zeit: Date.now(), antwort: a }); antworte(a); });
    return true;
  }
  if (m.typ === 'merke') { gewaehlt.set(sender.tab.id, { id: String(m.id), site: seite(url), zeit: Date.now() }); antworte({}); return; }
  if (m.typ === 'gewaehlt') {   // nur einmal, nur gleiche Seite, nur 3 min
    const g = gewaehlt.get(sender.tab.id);
    if (g && g.site === seite(url) && Date.now() - g.zeit < 180000) { gewaehlt.delete(sender.tab.id); antworte({ id: g.id }); } else antworte({});
    return;
  }
  if (m.typ === 'wert') { host({ typ: 'wert', url, id: String(m.id), was: String(m.was) }).then(antworte); return true; }
  antworte({ fehler: 'Unbekannte Anfrage' });
});
