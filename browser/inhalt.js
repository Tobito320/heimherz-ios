// Zeigt an Login-Feldern eine kleine Lumen-Liste; Klick füllt Benutzer und Passwort (oder den 2FA-Code).
(() => {
  const istPasswort = f => f.type === 'password';
  const istCode = f => f.autocomplete === 'one-time-code' || /otp|totp|2fa|mfa|token|verif|code/i.test(`${f.name} ${f.id} ${f.placeholder}`) && !istPasswort(f);
  const istBenutzer = f => /^(text|email|tel|)$/.test(f.type) && (/username|email/.test(f.autocomplete) || /user|login|mail|benutzer|kennung|account|anmeld/i.test(`${f.name} ${f.id} ${f.placeholder} ${f.getAttribute('aria-label') || ''}`));
  const sichtbar = f => f.getClientRects().length > 0 && !f.disabled && !f.readOnly;
  const felder = wurzel => [...(wurzel || document).querySelectorAll('input')].filter(sichtbar);
  const frage = m => new Promise(r => chrome.runtime.sendMessage(m, x => r(x || { fehler: chrome.runtime.lastError?.message })));

  const setze = (f, wert) => {
    f.focus();
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(f, wert);
    for (const t of ['input', 'change']) f.dispatchEvent(new Event(t, { bubbles: true }));
  };

  let box = null, cache = null;
  const zu = () => { box?.remove(); box = null; };

  async function zeige(feld) {
    zu();
    cache ??= await frage({ typ: 'liste' });
    const art = istCode(feld) ? 'code' : istPasswort(feld) || istBenutzer(feld) ? 'login' : null;
    const l = (cache.eintraege || []).filter(e => art === 'code' ? e.code : true);
    if (!art || (!l.length && !cache.fehler)) return;
    const r = feld.getBoundingClientRect();
    box = document.createElement('div');
    const s = box.attachShadow({ mode: 'closed' });   // Seite kann die Liste nicht lesen
    s.innerHTML = `<style>
      :host{all:initial}div.k{position:fixed;z-index:2147483647;min-width:240px;max-width:360px;background:#111;color:#fff;border-radius:12px;box-shadow:0 8px 24px #0006;font:13px system-ui,sans-serif;overflow:hidden}
      b{display:block;padding:8px 12px;font-size:11px;letter-spacing:.04em;color:#f5b25b;text-transform:uppercase}
      button{all:unset;display:block;box-sizing:border-box;width:100%;padding:8px 12px;cursor:pointer}button:hover,button:focus{background:#2a2a2a}
      small{display:block;color:#aaa}p{margin:0;padding:8px 12px;color:#f88}</style><div class=k></div>`;
    const k = s.querySelector('.k');
    k.style.left = `${Math.max(4, r.left)}px`; k.style.top = `${r.bottom + 4}px`;
    k.innerHTML = '<b>Lumen Cloud</b>';
    if (cache.fehler) { const p = document.createElement('p'); p.textContent = cache.fehler; k.append(p); cache = null; }
    for (const e of l) {
      const b = document.createElement('button');
      b.textContent = art === 'code' ? `Code: ${e.name}` : e.benutzer || e.name;
      const sm = document.createElement('small'); sm.textContent = e.name; b.append(sm);
      b.addEventListener('mousedown', ev => ev.preventDefault());   // Fokus bleibt im Feld
      b.addEventListener('click', () => fuelle(feld, e, art));
      k.append(b);
    }
    document.documentElement.append(box);
  }

  async function fuelle(feld, e, art) {
    zu();
    if (art === 'code') { const r = await frage({ typ: 'wert', id: e.id, was: 'code' }); if (r.wert) setze(feld, r.wert); return; }
    const alle = felder(feld.form);
    const pw = istPasswort(feld) ? feld : alle.find(istPasswort);
    const i = alle.indexOf(pw ?? feld);
    const benutzer = !istPasswort(feld) ? feld : alle.slice(0, Math.max(0, i)).reverse().find(f => /^(text|email|tel)$/.test(f.type));
    if (benutzer && e.benutzer) setze(benutzer, e.benutzer);   // Benutzer steht schon in der Liste, keine eigene Anfrage
    if (pw && e.passwort) { const r = await frage({ typ: 'wert', id: e.id, was: 'passwort' }); if (r.wert) setze(pw, r.wert); }
  }

  document.addEventListener('focusin', ev => { const f = ev.composedPath()[0]; if (f instanceof HTMLInputElement && sichtbar(f)) zeige(f); }, true);
  document.addEventListener('mousedown', ev => { if (box && !ev.composedPath().includes(box)) zu(); }, true);
  document.addEventListener('keydown', ev => { if (ev.key === 'Escape') zu(); }, true);
})();
