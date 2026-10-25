/// Eigene deutsche Wortliste für Wortgruppen-Passwörter: kleingeschrieben, ASCII (ä = ae, ö = oe, ü = ue, ß = ss), ohne Umlaute und Sonderzeichen.
/// Sie steht im Quelltext statt als Ressource, weil die AutoFill-Erweiterung (anderes Bundle) sie ebenfalls braucht.
enum Wortliste {
    static let woerter: [String] = text.split(whereSeparator: \.isWhitespace).map(String.init)

    private static let text = """
    abend acker adler adresse affe ahorn alarm album alge alpen alt ameise ampel amsel angel anker
    apfel apfelbaum apotheke april arbeit arm armband arzt asche aster astronaut atem atlas auge
    august ausflug auto bach backen baden bagger bahn balken balkon ball bambus banane bank bar
    bart bauch bauen bauer baum baumhaus becher becken beere beet bein beissen bellen berg bernstein
    besen besuch bett biber bibliothek biegen biene bild binden birke birne bitten bitter blank
    blass blatt blau blech blei bleiben bleistift blicken blind blitz blitzen block bluehen blueten
    blume blumentopf boden bogen bohne bonbon boot brand brav brechen breit brennen brett brezel
    brief brille bringen brot bruder bruecke brunnen brust buch buche buendel buerger bunt burg
    burger bus butter cafe cello chance chor clown dach dachs dackel dame damm dampf danken daumen
    decke decken degen delfin delikat denken diamant dicht dichter dick dienst dolch domino donau
    donner dorf dose drache drachen draht drehen drucken dschungel duenn duft duften dumm dunkel
    durst dusche eben echse eckball ehrlich eiche eichel eidechse eilen eimer einhorn eisbaer eisberg
    eisen eisig elch elefant elfe ellbogen ende eng engel ente erbse erdbeere erde erdnuss erfolg
    ernte esel eskimo essen essig eule fabrik fackel faden faehre faerben fahne fahren falke fallen
    fallschirm familie fangen farbe farn fasan fass faust feder fee feier feiern feige feile fein
    feld fell fenster ferien fern ferne fernrohr fest fett feuer fichte fieber film finden finger
    fingerhut fink fisch fit flach flagge flamingo flasche fleck fleissig fliege fliegen fliessen
    flink flocke floete flosse flott fluegel flug flughafen flur fluss foehn fohlen forelle forscher
    forst fotograf fracht frage fragen frau frech frei fremd freuen freund frieden friseur frisur
    froh fromm frosch frost frucht fruehling fuchs fuehlen fuellen fuss gabel gabelstapler gaertner
    galerie gallier gamsbock gans garten gasse gast gaumen geben gebirge gedicht gehen geige geist
    gelaende gelb gelten gemuese genie gepaeck gerade gerste geschenk gesicht gesund gewicht gewitter
    giessen gipfel giraffe gitarre gitter glas glatt gleis glocke glueck glueckskeks gnom gold goldfisch
    gondel gorilla graben gras grashuepfer grau greifen grenze griff grill grob gross grotte gruen
    gruppe guertel gummibaer gurke gut haare haben hafen hafer hagel hahn hai halb halm halten hammer
    hamster hand handtuch hang hangen hantel harfe hart hase haube heben hecht hecke heft heide
    heilen heimat heiss heiter heldin helfen helikopter hell helm hemd henne herbst herd hering
    himbeere himmel hirsch hirte hobel hoch hocker hoehle hoeren hohl holen holunder holz honig
    hopfen horn hose hotel huegel huepfen hufeisen huhn hummel hund hupe husten hut igel imker indigo
    ingwer insel iris jacke jagd jagen jaguar jahr januar jasmin jongleur jubel juli jung juni juwel
    kabel kabine kaefer kaenguru kaffee kahl kahn kakao kaktus kalender kalt kamel kamera kamin
    kamm kanal kanne kapitaen kapuze karotte karte karussell kastanie kasten kater katze kaufen
    kaugummi kaviar kegel kehren kelch kellner kennen kerl kern kerze kessel kette kiefer kiesel
    kinn kino kiosk kirche kirsche kissen kiste kiwi klar klavier klee kleid klein klettern klinge
    klingen klippe klug knapp knochen knopf knoten koala kobold koch kochen koenig koennen koffer
    kohl kokos kolibri komet kommen kompass kondor konzert kopf korallen korb korken korn kornblume
    kotelett kraehen kraeuter kraftvoll kragen kralle kran kranich kraut krebs kreide kreis krone
    kuchen kuehl kuerbis kuessen kugel kuh kuli kunst kupfer kurz kuss kutter labor lachen lachs
    laden lagune lahm lamm lampe land landen lanze laterne laub lauch laufen laut lawine leben lebkuchen
    leder leer legen lehm lehren leicht leihen leise leiter lerche lernen lesen leuchten lexikon
    libelle licht lieb liebe lieben liegen lilie limonade linde lineal linse lippe loben loch locker
    loeschen loewe lorbeer lotse lotsen lotus luchs luft luftballon luke lumpen lupe lupine lust
    mager magnet mahlen mais malen mandel mango mantel marder margerite markt marmelade marmor maske
    matrose mauer maulwurf maus meer mehl meiden meise melodie melone messen messer mikrofon milch
    mild minze mischen mitte moegen moewe mohn molch mond montag moos morgen motor motte muehle
    muffin mulde mund murmel muschel museum mut mutig mutter nachbar nackt nadel nadelbaum naehen
    nagel nah narzisse nase nashorn nass nebel nehmen nektar nelke nennen nest nett netz neu nicken
    nordpol note november nuance nudel nuss oase ober oboe oeffnen ofen ofenrohr offen ohr oktober
    olive olympia onkel opal orange orchidee orgel ostern otter ozean packen paddel pagode paket
    palast palme panda pantoffel papagei papier pappel paprika paradies park pass passend pause
    pavian pedal pelikan pelz pendel perle pfad pfahl pfanne pfau pfeffer pfeifen pfeil pferd pfirsich
    pflanzen pflaume pflegen pfluecken pfote phoenix picknick pier pilz pinguin pinsel pirat pizza
    plan planet platane platt platz plaudern pokal pol polarlicht pony portal post praline preis
    pudding pullover puls pumpe puppe putzen pyramide quader quaken quartett quarz quelle quitte
    rabatt rabe rad radieschen rahmen rakete rampe rand ranke rappe rasch rasen rasten raten rathaus
    rau rauchen raum raupe rechner reden regal regen regenbogen regnen reh reiben reich reifen reiher
    rein reis reisen reiten reiter rennen rente rentier rhein riechen riegel rinde ring ritter robbe
    rock rohr rollen roller rose rosine rost rot rubin rucksack rudel ruder rudern rufen ruhe ruhen
    ruhig ruine rund rutsche saal sacht sack saeen saege saft sage sagen salat salz samen sammeln
    sand sanft saphir satt sattel satz sauber sauer saugen sauna schach schaf schaffen schal scharf
    schatten schatz scheibe scheinen schenken schere scheune schieben schief schiff schildkroete
    schirm schlafen schlagen schlange schlank schleifen schlitten schloss schluessel schmecken schnecke
    schnee schneiden schnell schokolade schorle schrank schraube schreiben schreien schreiner schreiten
    schuh schule schwach schwalbe schwan schwarm schwer schwert schwimmen seehund seestern segel
    segler sehen seife seil sekunde selten semmel senden sense serie sessel setzen sicher sieb siegen
    silber singen sinken sinn sirene sitzen skizze socke sofa sommer sonne spaet spalten spargel
    spatz specht speer speicher spezi spiegel spiegelei spielen spinat spinne spitz splitter sporn
    sprechen springen sprosse spruch stab stachel stadion stahl stall stamm stark steckdose stecker
    steg stehen steigen steil stein stempel steppe sterben stern sticker stiefel stier still stirn
    stock stoff stolz stoppen storch strand strasse strauch strauss streiten strohhut strom studio
    stuecke stuhl stumm stunde sturm suchen suedpol suess sumpf suppe tabelle tacker tafel tag tal
    tanker tanne tante tanzen tapfer tasche tasse taube tauchen taucher teich teilen teller teppich
    thron tief tiger tinte tintenfisch tisch toast tomate tonne topas topf tornado torte torwart
    tourist tragen traktor traube traum trecker treffen treiben treppe tresor treten treu trichter
    trinken trocken trommel tropfen tulpe tunnel turm turnen tusche ueben ufer uhr uhu umhang unwetter
    urlaub urwald vanille vase vater veilchen ventil verein vesper vieh vogel vulkan waage wabe
    wache wachsen wachtel waffel wagen wal wald walnuss walze wand wanderer wandern wange wappen
    warm warten warze waschen wasser watte weben wecken wecker weg wehen weich weide weihnacht wein
    weinen weise weit weizen welle welpe wenden werfen wespe wiege wiegen wiese wikinger wild wimper
    wind windmuehle winken winter winzig wippe wirbel wissen witz wohnen wolf wolke wolle wuenschen
    wuerfel wuesten wurm wurst wurzel yoga zaeh zaehlen zahl zahm zahn zange zapfen zart zauber
    zaun zaunkoenig zebra zeder zeichnen zeigen zeit zeitung zelt zepter zeuge ziege ziegel ziehen
    ziel zielen zimmer zirkus zither zitrone zittern zopf zucker zug zwerg zwiebel zwilling zypresse
    """
}
