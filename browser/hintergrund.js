// Leitet Anfragen der Seite an den Host (heimherz) weiter. Die Seiten-URL kommt von Chrome (sender), nie von der Seite selbst.
chrome.runtime.onMessage.addListener((m, sender, antworte) => {
  const url = sender.url || '';
  if (!sender.tab || !/^https:\/\//.test(url)) { antworte({ fehler: 'Nur https-Seiten' }); return; }
  const anfrage = m.typ === 'liste' ? { typ: 'liste', url } : m.typ === 'wert' ? { typ: 'wert', url, id: String(m.id), was: String(m.was) } : null;
  if (!anfrage) { antworte({ fehler: 'Unbekannte Anfrage' }); return; }
  chrome.runtime.sendNativeMessage('com.lumen.cloud', anfrage, r => antworte(r || { fehler: chrome.runtime.lastError?.message || 'Lumen Cloud antwortet nicht' }));
  return true;
});
