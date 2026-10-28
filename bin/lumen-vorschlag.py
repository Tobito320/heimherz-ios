#!/usr/bin/env python3
# Lumen-Vorschlag (SPEC 30, W-054): Kästchen unter Login-Feldern in Apps (Vesktop, GTK, Qt) wie die Chrome-Erweiterung.
# Hört per AT-SPI auf Fokus in Eingabefeldern, zeigt passende Konten als Layer-Shell-Popup ohne Tastaturfokus,
# Klick ruft `heimherz tippe --id` (tippt per wtype ins weiter fokussierte Feld). Hier liegen nie Passwörter.
import json, os, re, subprocess, sys, threading, time

HEIMHERZ = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'heimherz')
FREMD = re.compile(r'chrome|chromium|zen|firefox|brave|vivaldi|kitty|alacritty|foot|wezterm|fuzzel', re.I)  # Browser haben die Erweiterung, Terminals keine Logins
FELDER = {'entry', 'password text', 'text'}
CODEFELD = re.compile(r'code|2fa|otp|totp|auth|token|verif|bestätig', re.I)
NEU_LADEN_S = 600


def passende(eintraege, fenster, feldname='', passwortfeld=False):
    """Konten fürs Fenster; im Code-Feld nur TOTP-Zeilen, sonst nur Login-Zeilen."""
    f = fenster.lower()
    treffer = [e for e in eintraege if any(w in f for w in e['woerter'])]
    if not passwortfeld and CODEFELD.search(feldname):
        return [dict(e, zeile_code=True) for e in treffer if e['code']]
    return [dict(e, zeile_code=False) for e in treffer]


def selbsttest():
    l = [{'id': '1', 'name': 'discord.com', 'benutzer': 'a@b.de', 'woerter': ['discord'], 'code': True},
         {'id': '2', 'name': 'Steam', 'benutzer': 's', 'woerter': ['steam'], 'code': False}]
    assert [e['id'] for e in passende(l, 'vesktop Discord')] == ['1']
    assert passende(l, 'vesktop Discord', 'Email or Phone Number')[0]['zeile_code'] is False
    assert passende(l, 'vesktop Discord', '6-digit authentication code')[0]['zeile_code'] is True
    assert passende(l, 'Steam', 'Code') == []
    assert passende(l, 'Steam', 'Password', passwortfeld=True)[0]['id'] == '2'
    assert passende(l, 'gimp') == []
    print('selbsttest ok')


def hypr_aktiv():
    try:
        return json.loads(subprocess.run(['hyprctl', '-j', 'activewindow'], capture_output=True, text=True, timeout=2).stdout or '{}')
    except Exception:
        return {}


def main():
    import gi
    gi.require_version('Atspi', '2.0'); gi.require_version('Gtk', '3.0'); gi.require_version('GtkLayerShell', '0.1')
    from gi.repository import Atspi, Gtk, GtkLayerShell, GLib, Gdk

    stand = {'eintraege': [], 'geladen': 0.0, 'laedt': False, 'feld': None, 'fenster': None, 'warm': None}

    def lade():
        if stand['laedt']:
            return
        stand['laedt'] = True
        def los():
            try:
                aus = subprocess.run([HEIMHERZ, 'vorschlag'], capture_output=True, text=True, timeout=30)
                if aus.returncode == 0:
                    stand['eintraege'], stand['geladen'] = json.loads(aus.stdout.strip().splitlines()[-1]), time.time()
            except Exception as x:
                print('vorschlag:', x, file=sys.stderr, flush=True)
            finally:
                stand['laedt'] = False
        threading.Thread(target=los, daemon=True).start()

    css = Gtk.CssProvider()
    css.load_from_data(b"""
      window { background: transparent; }
      .kasten { background: #1f1f23; border: 1px solid #3a3a42; border-radius: 10px; padding: 4px; }
      .kopf { color: #9a9aa5; font-size: 11px; padding: 4px 10px 2px 10px; }
      button.zeile { background: transparent; border: none; border-radius: 7px; padding: 6px 10px; box-shadow: none; }
      button.zeile:hover { background: #2e2e36; }
      .name { color: #f2f2f5; font-weight: 600; }
      .benutzer { color: #a8a8b3; font-size: 12px; }
    """)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    win = Gtk.Window()
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_namespace(win, 'lumen-vorschlag')
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE)  # Feld behält den Fokus, wtype tippt dorthin
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, True)
    GtkLayerShell.set_exclusive_zone(win, -1)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.get_style_context().add_class('kasten')
    win.add(box)

    def warm_zu():
        p, stand['warm'] = stand['warm'], None
        if p and p.poll() is None:
            try:
                p.stdin.close()   # EOF: `tippe --bereit` endet ohne zu tippen
            except OSError:
                pass

    def verstecke(*_):
        stand['feld'] = None
        warm_zu()
        win.hide()
        return False

    def waehle(_knopf, e, passwortfeld):
        art = 'code' if e['zeile_code'] else 'nur-passwort' if passwortfeld else ''
        p, stand['warm'] = stand['warm'], None
        try:   # vorgewärmt: Tresor ist schon offen, tippt sofort
            p.stdin.write(f"{e['id']} {art}\n".encode()); p.stdin.close()
        except (AttributeError, OSError):   # kein oder toter Vorlauf: kalt starten (rund 1,5 s)
            subprocess.Popen([HEIMHERZ, 'tippe', '--id', e['id']] + ([f'--{art}'] if art else []), stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        verstecke()
        stand['geladen'] = 0.0   # Reihenfolge nach Nutzung: beim nächsten Feld neu laden

    def zeige(x, y, breite, liste, passwortfeld):
        if not stand['warm'] or stand['warm'].poll() is not None:   # Tresor schon beim Zeigen öffnen, damit der Klick sofort tippt
            stand['warm'] = subprocess.Popen([HEIMHERZ, 'tippe', '--bereit'], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                             stderr=subprocess.DEVNULL, start_new_session=True)
        for k in box.get_children():
            box.remove(k)
        kopf = Gtk.Label(label='Lumen Cloud', xalign=0)
        kopf.get_style_context().add_class('kopf')
        box.pack_start(kopf, False, False, 0)
        # Zeilen merken, damit "lösch den zweiten" (Zappy, Agent) genau dieses Konto trifft: heimherz weg kasten:2
        try:
            ziel = os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'lumen-vorschlag.json')
            with open(ziel + '.neu', 'w') as d:
                json.dump({'zeit': time.time(), 'zeilen': [{'nr': i + 1, 'id': e['id'], 'name': e['name'], 'benutzer': e['benutzer']}
                                                          for i, e in enumerate(liste[:6])]}, d)
            os.replace(ziel + '.neu', ziel)
        except OSError:
            pass
        for e in liste[:6]:
            b = Gtk.Button()
            b.get_style_context().add_class('zeile')
            innen = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            # gross das Konto (Ahmed 28.10.: "directly show the itsdragonven"), klein die Seite, die er ohnehin kennt
            gross = 'Code' if e['zeile_code'] else e['benutzer'] or e['name']
            klein = e['name'] if gross != e['name'] else ('nur Passwort' if not e['benutzer'] else '')
            n = Gtk.Label(label=gross, xalign=0)
            n.get_style_context().add_class('name')
            innen.pack_start(n, False, False, 0)
            if klein:
                u = Gtk.Label(label=klein, xalign=0)
                u.get_style_context().add_class('benutzer')
                innen.pack_start(u, False, False, 0)
            b.add(innen)
            b.connect('clicked', waehle, e, passwortfeld)
            box.pack_start(b, False, False, 0)
        # shortcut: ein Monitor bei 0,0 angenommen; bei mehreren Monitoren Ausgabe per GtkLayerShell.set_monitor wählen
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.LEFT, max(0, x))
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.TOP, max(0, y))
        win.set_size_request(max(260, breite), -1)
        win.resize(1, 1)
        win.show_all()

    def fokus(ev):
        if not ev.detail1:
            return
        a = ev.source
        try:
            rolle, name = a.get_role_name(), a.get_name() or ''
            if rolle not in FELDER or not a.get_state_set().contains(Atspi.StateType.EDITABLE):
                return GLib.idle_add(verstecke)
            ext = a.get_extents(Atspi.CoordType.WINDOW)
        except Exception:
            return GLib.idle_add(verstecke)
        f = hypr_aktiv()
        klasse = f.get('class', '')
        if not klasse or FREMD.search(klasse):
            return GLib.idle_add(verstecke)
        if time.time() - stand['geladen'] > NEU_LADEN_S:
            lade()
        pw = rolle == 'password text'
        liste = passende(stand['eintraege'], f'{klasse} {f.get("title", "")}', name, pw)
        print(f'feld {rolle} "{name[:40]}" in {klasse}: {len(liste)} von {len(stand["eintraege"])}', flush=True)   # Journal, nie Werte
        if not liste:
            return GLib.idle_add(verstecke)
        x0, y0 = f.get('at', [0, 0])
        stand['feld'], stand['fenster'] = a, f.get('address')
        GLib.idle_add(zeige, x0 + ext.x, y0 + ext.y + ext.height + 4, ext.width, liste, pw)

    def getippt(ev):
        if stand['feld'] is not None and ev.source == stand['feld']:
            GLib.idle_add(verstecke)

    def wache():
        # Fensterwechsel (anderer Workspace, Alt+Tab) meldet AT-SPI nicht: dann zu
        if stand['feld'] is not None and hypr_aktiv().get('address') != stand['fenster']:
            verstecke()
        return True

    l1 = Atspi.EventListener.new(fokus); l1.register('object:state-changed:focused')
    l2 = Atspi.EventListener.new(getippt); l2.register('object:text-changed:insert')
    GLib.timeout_add(400, wache)
    lade()
    if '--zeige-test' in sys.argv:   # nur Darstellung prüfen: Popup 3 s an fester Stelle, Klick tippt nichts
        GLib.idle_add(zeige, 400, 300, 414, [{'id': '-', 'name': 'discord.com', 'benutzer': 'test@lumen.local', 'zeile_code': False}], False)
        GLib.timeout_add(3000, Gtk.main_quit)
    Gtk.main()


if __name__ == '__main__':
    selbsttest() if '--selbsttest' in sys.argv else main()
