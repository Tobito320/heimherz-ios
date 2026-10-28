// Lumen-Liste unter Login-Feldern, im Stil der Seite (hell/dunkel) und des Lumen-Kits; Klick oder Enter füllt Benutzer und Passwort (oder den 2FA-Code).
(() => {
  const istPasswort = f => f.type === 'password';
  const istCode = f => !istPasswort(f) && (f.autocomplete === 'one-time-code' || /otp|totp|2fa|mfa|token|verif|code/i.test(`${f.name} ${f.id} ${f.placeholder}`));
  const istBenutzer = f => /^(text|email|tel|)$/.test(f.type) && (/username|email/.test(f.autocomplete) || /user|login|mail|benutzer|kennung|account|anmeld|phone|handy/i.test(`${f.name} ${f.id} ${f.placeholder} ${f.getAttribute('aria-label') || ''}`));
  const sichtbar = f => f.getClientRects().length > 0 && !f.disabled && !f.readOnly;
  const felder = wurzel => [...(wurzel || document).querySelectorAll('input')].filter(sichtbar);
  const frage = m => new Promise(r => chrome.runtime.sendMessage(m, x => r(x || { fehler: chrome.runtime.lastError?.message })));

  const setze = (f, wert) => {
    f.focus();
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(f, wert);
    for (const t of ['input', 'change']) f.dispatchEvent(new Event(t, { bubbles: true }));
  };

  // Seite dunkel? Erste nicht durchsichtige Hintergrundfarbe vom Feld nach oben.
  const dunkel = el => {
    for (let e = el; e; e = e.parentElement) {
      const m = getComputedStyle(e).backgroundColor.match(/[\d.]+/g);
      if (m && (m[3] === undefined || +m[3] > 0.5)) return (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) < 128;
    }
    return matchMedia('(prefers-color-scheme: dark)').matches;
  };

  const CSS = `
    :host{all:initial}
    .k{position:fixed;z-index:2147483647;box-sizing:border-box;padding:6px;border-radius:14px;font:14px/1.3 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif;
      background:var(--karte);color:var(--tinte);border:1px solid var(--rand);box-shadow:0 12px 32px rgba(0,0,0,.28),0 2px 6px rgba(0,0,0,.12);
      max-height:300px;overflow:auto;animation:auf .14s cubic-bezier(.2,.8,.2,1);transform-origin:top}
    .k.d{--karte:rgba(22,22,24,.96);--tinte:#fff;--tinte2:#B0B3B8;--chip:#2A2A2D;--rand:rgba(255,255,255,.08);--akzent:#6EA8FF}
    .k.h{--karte:rgba(255,255,255,.98);--tinte:#191C1F;--tinte2:#565B62;--chip:#EAEAEC;--rand:rgba(0,0,0,.08);--akzent:#0058D6}
    @keyframes auf{from{opacity:0;transform:translateY(-4px) scale(.98)}}
    .kopf{display:flex;align-items:center;gap:6px;padding:4px 8px 6px;font-size:11px;font-weight:600;letter-spacing:.02em;color:var(--tinte2)}
    .logo{width:12px;height:12px;border-radius:50%;background:radial-gradient(circle at 35% 35%,#fff 0,#9CC3FF 25%,#3D8BFF 60%,#6E4BFF 100%);box-shadow:0 0 8px #3D8BFF88}
    button{all:unset;display:flex;align-items:center;gap:10px;box-sizing:border-box;width:100%;padding:8px;border-radius:10px;cursor:pointer}
    button.an,button:hover{background:var(--chip)}
    .av{flex:none;font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;width:30px;height:30px;border-radius:50%;display:grid;place-items:center;font-weight:600;font-size:13px;color:#fff;background:linear-gradient(135deg,#3D8BFF,#6E4BFF)}
    .av.bild{background:var(--chip)}.av img{width:18px;height:18px;border-radius:4px}
    .t{min-width:0}.t b,.t small{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .t b{font-weight:500}.t small{font-size:12px;color:var(--tinte2);margin-top:1px}
    .leise{padding:6px 8px 4px;font-size:12px;color:var(--tinte2)}`;

  let box = null, k = null, feld = null, cache = null, wahl = 0;
  const knoepfe = () => k ? [...k.querySelectorAll('button')] : [];
  const markiere = i => { const b = knoepfe(); if (!b.length) return; wahl = (i + b.length) % b.length; b.forEach((x, j) => x.classList.toggle('an', j === wahl)); b[wahl].scrollIntoView({ block: 'nearest' }); };
  const zu = () => { box?.remove(); box = k = feld = null; };
  const lege = () => {
    if (!k || !feld?.isConnected) return zu();
    const r = feld.getBoundingClientRect(), w = Math.max(r.width, 260);
    k.style.width = `${w}px`;
    k.style.left = `${Math.min(Math.max(4, r.left), innerWidth - w - 4)}px`;
    const unten = r.bottom + 6, hoch = k.offsetHeight;
    k.style.top = `${unten + hoch > innerHeight && r.top - hoch - 6 > 0 ? r.top - hoch - 6 : unten}px`;
  };

  const symbol = document.querySelector('link[rel~="icon"],link[rel="apple-touch-icon"]')?.href || `${location.origin}/favicon.ico`;
  const zeile = (titel, unter, buchstabe) => {
    const b = document.createElement('button');
    b.innerHTML = '<span class=av></span><span class=t><b></b><small></small></span>';
    const av = b.querySelector('.av'), bild = document.createElement('img');
    av.textContent = (buchstabe || '?').slice(0, 1).toUpperCase();
    bild.src = symbol; bild.onload = () => { av.textContent = ''; av.classList.add('bild'); av.append(bild); };   // Symbol der Seite selbst, keine fremde Anfrage
    b.querySelector('b').textContent = titel; b.querySelector('small').textContent = unter;
    b.addEventListener('mousedown', ev => ev.preventDefault());   // Fokus bleibt im Feld
    return b;
  };

  async function zeige(f) {
    const art = istCode(f) ? 'code' : istPasswort(f) || istBenutzer(f) ? 'login' : null;
    if (!art) return zu();
    const c = await (cache ??= frage({ typ: 'liste' }));
    if (document.activeElement !== f && f.getRootNode().activeElement !== f) return;   // Fokus ist schon weiter
    const l = (c.eintraege || []).filter(e => art === 'code' ? e.code : true);
    if (c.fehler) console.debug('Lumen Cloud:', c.fehler);
    if (!l.length) { if (c.fehler) cache = null; return zu(); }   // nichts Passendes: leise bleiben
    zu(); feld = f;
    box = document.createElement('div');
    const s = box.attachShadow({ mode: 'closed' });   // Seite kann die Liste nicht lesen
    s.innerHTML = `<style>${CSS}</style><div class="k ${dunkel(f) ? 'd' : 'h'}" role=listbox><div class=kopf><span class=logo></span>Lumen Cloud</div></div>`;
    k = s.querySelector('.k');
    for (const e of l) {
      const b = art === 'code' ? zeile('Code einsetzen', e.benutzer || e.name, e.name) : zeile(e.benutzer || e.name, e.name, e.name);
      b.addEventListener('click', () => fuelle(f, e, art));
      k.append(b);
    }
    document.documentElement.append(box);
    lege(); markiere(0);
  }

  async function fuelle(f, e, art) {
    zu();
    if (art === 'code') { const r = await frage({ typ: 'wert', id: e.id, was: 'code' }); if (r.wert) setze(f, r.wert); return; }
    const alle = felder(f.form);
    const pw = istPasswort(f) ? f : alle.find(istPasswort);
    const i = alle.indexOf(pw ?? f);
    const benutzer = !istPasswort(f) ? f : alle.slice(0, Math.max(0, i)).reverse().find(x => /^(text|email|tel)$/.test(x.type));
    if (benutzer && e.benutzer) setze(benutzer, e.benutzer);   // Benutzer steht schon in der Liste, keine eigene Anfrage
    if (pw && e.passwort) { const r = await frage({ typ: 'wert', id: e.id, was: 'passwort' }); if (r.wert) setze(pw, r.wert); }
  }

  document.addEventListener('focusin', ev => { const f = ev.composedPath()[0]; if (f instanceof HTMLInputElement && sichtbar(f)) zeige(f); }, true);
  document.addEventListener('mousedown', ev => { if (!box || ev.composedPath().includes(box)) return; if (ev.composedPath()[0] !== feld) zu(); }, true);
  document.addEventListener('keydown', ev => {
    if (!box) { if (ev.key === 'ArrowDown' && ev.composedPath()[0] instanceof HTMLInputElement) zeige(ev.composedPath()[0]); return; }
    if (ev.key === 'Escape') zu();
    else if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') { ev.preventDefault(); markiere(wahl + (ev.key === 'ArrowDown' ? 1 : -1)); }
    else if (ev.key === 'Enter') { ev.preventDefault(); ev.stopPropagation(); knoepfe()[wahl]?.click(); }
    else if (ev.key === 'Tab') zu();
  }, true);
  document.addEventListener('input', ev => { if (box && ev.isTrusted) zu(); }, true);   // wer selbst tippt, will die Liste nicht
  addEventListener('scroll', lege, true); addEventListener('resize', lege);
  // Vorab laden, sobald Login-Felder da sind (auch wenn die Seite sie erst später zeichnet): die Liste steht dann beim Klick sofort
  const vorab = () => { if (!cache && felder().some(f => istPasswort(f) || istBenutzer(f) || istCode(f))) cache = frage({ typ: 'liste' }).then(r => { if (r.fehler) cache = null; return r; }); };
  vorab(); for (const ms of [500, 1500, 4000]) setTimeout(vorab, ms);
})();
