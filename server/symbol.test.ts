import { afterAll, describe, expect, test } from 'bun:test';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { bildTyp, gueltigerHost, ipBytes, istOeffentlich, symbolLinks, type Antwort, type Holer } from './symbol';
import { baue } from './testhilfe';

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 1, 2, 3]);
const ICO = new Uint8Array([0, 0, 1, 0, 1, 0, 16, 16, 0, 0, 1, 0, 32, 0]);
const SVG = new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
const html = (s: string) => new TextEncoder().encode(s);
const ok = (body: Uint8Array, typ = 'image/png'): Antwort => ({ status: 200, kopf: { 'content-type': typ }, body });
const weiter = (nach: string): Antwort => ({ status: 302, kopf: { location: nach }, body: new Uint8Array() });
const nichts: Antwort = { status: 404, kopf: {}, body: new Uint8Array() };

describe('Adressen', () => {
  test('öffentlich und privat an den Grenzen (IPv4)', () => {
    const privat = ['0.0.0.0', '0.1.2.3', '10.0.0.1', '10.255.255.255', '127.0.0.1', '127.255.255.254', '169.254.169.254', '172.16.0.0', '172.31.255.255',
      '192.168.0.1', '192.168.255.255', '100.64.0.0', '100.100.100.100', '100.127.255.255', '224.0.0.1', '239.255.255.255', '240.0.0.1', '255.255.255.255',
      '198.18.0.1', '198.19.255.255', '192.0.2.1', '192.0.0.8'];
    const oeffentlich = ['8.8.8.8', '1.1.1.1', '172.15.255.255', '172.32.0.0', '100.63.255.255', '100.128.0.0', '192.167.255.255', '192.169.0.0',
      '11.0.0.1', '9.255.255.255', '169.253.255.255', '169.255.0.0', '198.17.255.255', '198.20.0.0', '223.255.255.255'];
    for (const ip of privat) expect([ip, istOeffentlich(ip)]).toEqual([ip, false]);
    for (const ip of oeffentlich) expect([ip, istOeffentlich(ip)]).toEqual([ip, true]);
  });

  test('IPv6: lokal, privat, Tailnet-fähige Bereiche und eingebettetes IPv4', () => {
    const privat = ['::', '::1', 'fc00::1', 'fd12:3456::1', 'fdff:ffff::1', 'fe80::1', 'febf::1', 'fec0::1', 'ff02::1', '::ffff:127.0.0.1', '::ffff:10.1.2.3',
      '::ffff:7f00:1', '::ffff:a9fe:a9fe', '::ffff:100.64.0.1', '64:ff9b::a00:1', '2001:db8::1', '::10.0.0.1', '0:0:0:0:0:ffff:c0a8:1', '100::1'];
    const oeffentlich = ['2606:4700:4700::1111', '2001:4860:4860::8888', 'fbff::1', 'fe00::1', '::ffff:8.8.8.8', '::ffff:808:808', '64:ff9b::808:808', '2a00:1450::1'];
    for (const ip of privat) expect([ip, istOeffentlich(ip)]).toEqual([ip, false]);
    for (const ip of oeffentlich) expect([ip, istOeffentlich(ip)]).toEqual([ip, true]);
  });

  test('Müll ist nie öffentlich', () => {
    for (const x of ['', 'abc', '1.2.3', '1.2.3.4.5', '256.1.1.1', 'fe80::1%eth0', ':::', '1::2::3', '2130706433', '0x7f.0.0.1', '1.2.3.4/8'])
      expect([x, istOeffentlich(x)]).toEqual([x, false]);
    expect(ipBytes('::1')).toEqual([...Array(15).fill(0), 1]);
    expect(ipBytes('1:2:3:4:5:6:7:8')).toEqual([0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0, 7, 0, 8]);
  });
});

describe('Hostnamen', () => {
  test('gültige öffentliche Namen', () => {
    expect(gueltigerHost('GitHub.com')).toBe('github.com');
    expect(gueltigerHost(' www.example.org ')).toBe('www.example.org');
    expect(gueltigerHost('xn--bcher-kva.example')).toBe('xn--bcher-kva.example');
    expect(gueltigerHost('a-b.co.uk')).toBe('a-b.co.uk');
  });

  test('alles andere wird abgelehnt', () => {
    const schlecht = ['', 'localhost', 'x.localhost', 'drucker.local', 'nas.lan', 'pc.home.arpa', 'tobi-1.tail1234.ts.net', 'ts.net', 'intern.internal', 'a.invalid',
      '127.0.0.1', '10.0.0.1', '[::1]', '::1', '2130706433', '0x7f.1', '1.2.3.4', 'example.com:8443', 'user@example.com', 'a/b.example.com', '../x', '%2e%2e',
      '%2e%2e.example.com', 'example.com/', 'example.com?x', 'exa mple.com', 'example', '.example.com', 'example.com.', '-a.example.com', 'a-.example.com',
      'a..example.com', 'ex\u0000ample.com', 'bücher.example', 'x.123', `${'a'.repeat(64)}.example.com`, `${'a.'.repeat(130)}com`, 'example.c'];
    for (const h of schlecht) expect([h, gueltigerHost(h)]).toEqual([h, null]);
    expect(gueltigerHost(null)).toBeNull();
    expect(gueltigerHost(undefined)).toBeNull();
  });
});

describe('Bilder und Links', () => {
  test('Typ nach den ersten Bytes', () => {
    expect(bildTyp(PNG)).toBe('image/png');
    expect(bildTyp(ICO)).toBe('image/x-icon');
    expect(bildTyp(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...Array(12).fill(0)]))).toBe('image/jpeg');
    expect(bildTyp(new Uint8Array([...html('RIFF'), 1, 2, 3, 4, ...html('WEBPVP8 ')]))).toBe('image/webp');
    expect(bildTyp(SVG)).toBeNull();
    expect(bildTyp(html('<html><body>hallo</body></html>'))).toBeNull();
    expect(bildTyp(new Uint8Array())).toBeNull();
  });

  test('Symbol-Links: Apple zuerst, größere vor kleineren, relative Adressen', () => {
    const basis = new URL('https://example.org/app/start');
    const links = symbolLinks(`<head>
      <link rel="icon" href="/klein.png" sizes="16x16">
      <link rel='shortcut icon' href=sym.ico>
      <link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
      <link rel="icon" href="https://cdn.example.net/gross.png?a=1&amp;b=2" sizes="192x192">
      <link rel="stylesheet" href="/x.css"><link rel="icon">
    </head>`, basis).map(u => u.href);
    expect(links).toEqual(['https://example.org/apple.png', 'https://cdn.example.net/gross.png?a=1&b=2', 'https://example.org/klein.png', 'https://example.org/app/sym.ico']);
  });
});

describe('Dienst', () => {
  type Aufruf = { url: string; ip: string };
  function aufbau(regeln: (url: URL, n: number) => Antwort | Error, dns: (h: string) => string[] | Error = () => ['93.184.216.34'], extra: { jetzt?: () => number; pause?: () => Promise<void> } = {}) {
    const aufrufe: Aufruf[] = [];
    const aufgeloest: string[] = [];
    let n = 0, gleichzeitig = 0, spitze = 0;
    const holer: Holer = async (url, ip) => {
      aufrufe.push({ url: url.href, ip: ip.address });
      gleichzeitig++; spitze = Math.max(spitze, gleichzeitig);
      try {
        await extra.pause?.();
        const r = regeln(url, n++);
        if (r instanceof Error) throw r;
        return r;
      } finally { gleichzeitig--; }
    };
    const t = baue({ symbole: { holer, jetzt: extra.jetzt, aufloeser: async h => { aufgeloest.push(h); const r = dns(h); if (r instanceof Error) throw r; return r; } } });
    return { t, aufrufe, aufgeloest, spitze: () => spitze };
  }
  const toDispose: { ende: () => void }[] = [];
  afterAll(() => toDispose.forEach(x => x.ende()));
  const neu = (...a: Parameters<typeof aufbau>) => { const x = aufbau(...a); toDispose.push(x.t); return x; };

  test('ohne Token 401, mit Token Parameterfehler 400 und der Holer wird nie gerufen', async () => {
    const x = neu(() => ok(PNG));
    expect((await x.t.ohne('/v1/symbol?host=example.org')).status).toBe(401);
    for (const h of ['', 'localhost', '127.0.0.1', '../x', '%2e%2e', 'example.org:8443', 'user@example.org', 'a/b.example.org', 'nas.local', 'x.ts.net'])
      expect([h, (await x.t.f(`/v1/symbol?host=${encodeURIComponent(h)}`)).status]).toEqual([h, 400]);
    expect((await x.t.f('/v1/symbol')).status).toBe(400);
    expect(x.aufrufe).toEqual([]);
    expect(x.aufgeloest).toEqual([]);
  });

  test('Apple-Symbol zuerst, Bild kommt mit Typ zurück und liegt danach im Cache', async () => {
    const x = neu(u => (u.pathname === '/apple-touch-icon.png' ? ok(PNG) : nichts));
    const r = await x.t.f('/v1/symbol?host=Beispiel.example');
    expect([r.status, r.headers.get('content-type'), r.headers.get('x-content-type-options')]).toEqual([200, 'image/png', 'nosniff']);
    expect(new Uint8Array(await r.arrayBuffer())).toEqual(PNG);
    expect(x.aufrufe).toEqual([{ url: 'https://beispiel.example/apple-touch-icon.png', ip: '93.184.216.34' }]);
    const r2 = await x.t.f('/v1/symbol?host=beispiel.example');
    expect(r2.status).toBe(200);
    expect(x.aufrufe.length).toBe(1);
  });

  test('ohne Apple-Symbol: Link aus dem HTML, sonst favicon.ico', async () => {
    const a = neu(u => {
      if (u.pathname === '/') return ok(html('<link rel="icon" href="/bild/s.png">'), 'text/html; charset=utf-8');
      return u.pathname === '/bild/s.png' ? ok(PNG) : nichts;
    });
    expect((await a.t.f('/v1/symbol?host=seite.example')).status).toBe(200);
    expect(a.aufrufe.map(c => new URL(c.url).pathname)).toEqual(['/apple-touch-icon.png', '/', '/bild/s.png']);

    const b = neu(u => (u.pathname === '/favicon.ico' ? ok(ICO, 'image/vnd.microsoft.icon') : nichts));
    const r = await b.t.f('/v1/symbol?host=alt.example');
    expect([r.status, r.headers.get('content-type')]).toEqual([200, 'image/x-icon']);
    expect(b.aufrufe.map(c => new URL(c.url).pathname)).toEqual(['/apple-touch-icon.png', '/', '/favicon.ico']);
  });

  test('kein Bild: 404, und "kein Symbol" wird gemerkt', async () => {
    const x = neu(() => nichts);
    expect((await x.t.f('/v1/symbol?host=leer.example')).status).toBe(404);
    const n = x.aufrufe.length;
    expect(n).toBeGreaterThan(0);
    expect((await x.t.f('/v1/symbol?host=leer.example')).status).toBe(404);
    expect(x.aufrufe.length).toBe(n);
  });

  test('Typ zählt nach den Bytes: HTML als image/png und SVG werden verworfen', async () => {
    const x = neu(() => ok(html('<html>kein Bild, nur behauptet</html>'), 'image/png'));
    expect((await x.t.f('/v1/symbol?host=luege.example')).status).toBe(404);
    const y = neu(() => ok(SVG, 'image/svg+xml'));
    expect((await y.t.f('/v1/symbol?host=svg.example')).status).toBe(404);
  });

  test('Cache läuft nach 30 Tagen ab', async () => {
    let jetzt = 1_800_000_000_000;
    const x = neu(() => ok(PNG), () => ['93.184.216.34'], { jetzt: () => jetzt });
    await x.t.f('/v1/symbol?host=alt.example');
    jetzt += 29 * 864e5;
    await x.t.f('/v1/symbol?host=alt.example');
    expect(x.aufrufe.length).toBe(1);
    jetzt += 2 * 864e5;
    await x.t.f('/v1/symbol?host=alt.example');
    expect(x.aufrufe.length).toBe(2);
  });

  test('Netzfehler wird nur kurz gemerkt, ein sauberes "nichts da" lange', async () => {
    let jetzt = 1_800_000_000_000;
    const x = neu(() => new Error('Zeit'), () => ['93.184.216.34'], { jetzt: () => jetzt });
    expect((await x.t.f('/v1/symbol?host=wackelt.example')).status).toBe(404);
    const n = x.aufrufe.length;
    jetzt += 30 * 60_000;
    await x.t.f('/v1/symbol?host=wackelt.example');
    expect(x.aufrufe.length).toBe(n);
    jetzt += 40 * 60_000;
    await x.t.f('/v1/symbol?host=wackelt.example');
    expect(x.aufrufe.length).toBeGreaterThan(n);
  });

  test('SSRF: private, lokale und Tailnet-Adressen (auch nur eine von mehreren) werden nie angefragt', async () => {
    for (const ips of [['127.0.0.1'], ['10.1.2.3'], ['192.168.1.5'], ['172.16.0.9'], ['169.254.169.254'], ['100.64.1.2'], ['::1'], ['fd00::5'], ['fe80::1'],
      ['93.184.216.34', '10.0.0.1'], ['2606:4700::1111', '127.0.0.1'], ['::ffff:192.168.0.1'], []]) {
      const x = neu(() => ok(PNG), () => ips);
      expect([ips, (await x.t.f('/v1/symbol?host=boese.example')).status]).toEqual([ips, 404]);
      expect([ips, x.aufrufe]).toEqual([ips, []]);
    }
  });

  test('Weiterleitung auf private Adresse, auf http oder auf Fremdport wird nicht verfolgt', async () => {
    const dns = (h: string) => (h === 'intern.example' ? ['10.0.0.7'] : ['93.184.216.34']);
    for (const ziel of ['https://intern.example/x.png', 'http://oeffentlich.example/x.png', 'https://oeffentlich.example:8443/x.png', 'https://localhost/x.png',
      'https://127.0.0.1/x.png', 'https://user:pw@oeffentlich.example/x.png', 'file:///etc/passwd', 'ftp://oeffentlich.example/x']) {
      const x = neu(u => (u.hostname === 'start.example' ? weiter(ziel) : ok(PNG)), dns);
      expect([ziel, (await x.t.f('/v1/symbol?host=start.example')).status]).toEqual([ziel, 404]);
      expect([ziel, x.aufrufe.every(a => new URL(a.url).hostname === 'start.example')]).toEqual([ziel, true]);
    }
  });

  test('Weiterleitung auf eine andere öffentliche Seite geht, aber höchstens 3 Sprünge', async () => {
    const gut = neu(u => (u.hostname === 'start.example' ? weiter('https://ziel.example/icon.png') : ok(PNG)));
    expect((await gut.t.f('/v1/symbol?host=start.example')).status).toBe(200);
    expect(gut.aufgeloest).toEqual(['start.example', 'ziel.example']);

    const kette = neu(u => weiter(`https://k${u.pathname.length}.example/${'x'.repeat(u.pathname.length)}`));
    expect((await kette.t.f('/v1/symbol?host=start.example')).status).toBe(404);
    // je Versuch (Apple-Symbol, HTML, favicon) höchstens 4 Anfragen
    expect(kette.aufrufe.length).toBeLessThanOrEqual(12);
  });

  test('Verbindung geht an die geprüfte Adresse', async () => {
    const x = neu(() => ok(PNG), () => ['2606:4700:4700::1111']);
    await x.t.f('/v1/symbol?host=sechs.example');
    expect(x.aufrufe[0].ip).toBe('2606:4700:4700::1111');
  });

  test('gleiche Anfragen gleichzeitig werden zusammengelegt, parallel höchstens vier Hosts', async () => {
    const pause = () => new Promise<void>(r => setTimeout(r, 20));
    const x = neu(u => (u.pathname === '/apple-touch-icon.png' ? ok(PNG) : nichts), () => ['93.184.216.34'], { pause });
    const einer = await Promise.all(Array.from({ length: 6 }, () => x.t.f('/v1/symbol?host=eins.example')));
    expect(einer.map(r => r.status)).toEqual([200, 200, 200, 200, 200, 200]);
    expect(x.aufrufe.length).toBe(1);
    const viele = await Promise.all(Array.from({ length: 12 }, (_, i) => x.t.f(`/v1/symbol?host=h${i}.example`)));
    expect(viele.every(r => r.status === 200)).toBe(true);
    expect(x.spitze()).toBeLessThanOrEqual(4);
    expect(x.spitze()).toBeGreaterThan(1);
  });

  test('Ablage: Ordner 0700, Dateien 0600, Namen sind Hashes (kein Host im Dateinamen)', async () => {
    const x = neu(() => ok(PNG));
    await x.t.f('/v1/symbol?host=ablage.example');
    const ordner = join(x.t.daten, 'symbole');
    expect(statSync(ordner).mode & 0o777).toBe(0o700);
    const namen = readdirSync(ordner);
    expect(namen.length).toBe(2);
    for (const n of namen) {
      expect(n).toMatch(/^[0-9a-f]{64}\.(bin|json)$/);
      expect(statSync(join(ordner, n)).mode & 0o777).toBe(0o600);
    }
  });
});
