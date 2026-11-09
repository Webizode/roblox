# Wobble Scoops: Projektstand und Entscheidungen

Stand: 24.10.2026 (Gespräch mit Claude). Diese Datei ist die aktuelle Hauptquelle. Sie ersetzt die ChatGPT-Zusammenfassung vom 24.10.2026, wo sie ihr widerspricht. Die verbindlichen Design-Regeln stehen zusätzlich in `docs/design-regeln.md`.

---

## 1. Was Wobble Scoops ist

Roblox-PvP-Spiel auf einem offenen Pier. Die Eismaschine **Big Swirl** schießt Eiskugeln. Spieler fangen sie und stapeln sie als **wackelnden Turm** in der Waffel auf ihrem Rücken. Zum Angreifen halten sie **lebendige Attack-Scoops** mit Gesicht, Fähigkeit und Emotionen in der Hand und **werfen** sie auf andere.

**Zwei verschiedene Kugel-Arten (nicht verwechseln):**
- **Turm-Kugeln:** werden gefangen und gestapelt, sind Beute und Wert. Kein Gesicht, keine Emotionen.
- **Attack-Scoops:** in der Hand, werden geworfen, haben Gesicht, Persönlichkeit, Emotionen und Sorten-Fähigkeit. Werden nicht gestapelt. Der Turm ist der Einsatz: Alles, was man trägt, kann einem weggeschossen werden. Sicher ist es erst nach dem **Servieren am eigenen Plot** (früher Wagen).

**In einem Satz:** Stapel hoch, wirf gut, bring deine Beute nach Hause, bevor dich jemand abschießt.

**Wichtige Korrektur zur ChatGPT-Version:** Es ist kein reines Wurf-/Kampfspiel mit 30–90-Sekunden-Runden. Das Kern-Verb im Code ist das Balancieren des Turms; PvP ist der Kern im Moment-zu-Moment-Spiel, der Turm ist das, worum gekämpft wird.

---

## 2. Getroffene Entscheidungen (24.10.2026)

| Thema | Entscheidung |
|---|---|
| Schwerpunkt | PvP zuerst im Spielgefühl, Sammeln als Grund zum Wiederkommen |
| Server-Modell | **Offener Server**, kein Matchmaking, keine Lobby |
| Arena-Gefühl | **Kurze Events** (ca. 3 Min.) alle paar Minuten, z. B. „Scoop Rush“, „höchster Turm gewinnt“ |
| Einsatz | Getragener Turm ist ungesichert, Servieren sichert |
| Beute | Verschüttete Kugeln anderer können eingesammelt werden (gebaut, `LootService`) |
| Führende | Große Türme leuchten (Golden Glow) und werden zum Ziel |
| Fairness | 30 % (mind. 2) bleiben beim Kippen, 3 s Vorrang auf eigene Kugeln, Türme unter 5 Kugeln geschützt; außerhalb der Arena (Safe Zone, seit 30.10.2026) keine Treffer und kein Kippen |
| Angriff | Einzige Angriffsaktion: Werfen. Kein Nahkampf |
| Sorten | Sidegrades mit Fähigkeiten, nie stärker. Kein Pay-to-Win |
| Scoops | Lebendig: Gesicht, Persönlichkeit, Emotionen, reagieren auf das Spiel |

---

## 3. Design-Regeln (Kurzfassung)

1. Der Turm ist dein Einsatz.
2. Wer hoch stapelt, wird gejagt.
3. Treffen fühlt sich stark an, getroffen werden fühlt sich fair an.
4. Verlieren tut weh, aber nie komplett.
5. Sorten sind anders, nicht stärker.
6. Smooth vor Features.
7. Die Scoops leben.
8. Bestehendes wird erweitert, nicht ersetzt.

---

## 4. Emotionssystem der Scoops

Ein gemeinsames System für alle Sorten (Ereignis → Emotion, Dauer, Priorität, alles in einer Config).

| Emotion | Auslöser | Wirkung |
|---|---|---|
| Freude / Jubel | Treffer, Knockdown, großer Turm serviert | nur Optik, andere sehen es |
| Wut | 2× kurz hintereinander getroffen oder Kugeln verloren | nächster Wurf ist „Wut-Wurf“ mit etwas mehr Turm-Stoß (Comeback, kein Schaden-Bonus) |
| Angst | eigener Turm ächzt oder kippt gleich | Warnsignal, Gesicht ist Teil der Anzeige |
| Überraschung | im Flug, kurz vor dem Aufprall | nur Optik |
| Splat | Aufprall | kurzes Zerquetschen, dann Effekt |
| Idle | länger nichts passiert | blinzeln, umschauen, wippen |

**Technik:**
- Gesichter als austauschbare Texturen (Augen und Mund getrennt), nicht ins Modell eingebacken
- 5–6 Ausdrücke reichen
- Squash and Stretch, Wippen, Zittern prozedural im Code, keine eigene Animation pro Sorte
- Pro Sorte nur Farbe, kleines Merkmal, Persönlichkeit, Sound
- Lesbar auf ca. 20 Studs und im Flug
- Gilt nur für die Attack-Scoops in der Hand, nicht für die Turm-Kugeln

---

## 5. Sorten-Startset

| Sorte | Fähigkeit | Persönlichkeit |
|---|---|---|
| Vanille | Allrounder, gerader Flug | freundlich, ausgeglichen |
| Erdbeere | springt einmal ab | verspielt, frech |
| Minze | verlangsamt kurz beim Treffer | cool, gelassen |
| Chili | mehr Turm-Stoß, weniger Reichweite | hitzköpfig, wird schnell wütend |

Weitere Sorten (Schoko, Blaubeere, Rainbow usw.) erst nach erfolgreichem Playtest.

---

## 6. Modell: Attack-Scoop (Vorgabe für den Modeler)

Der Attack-Scoop ist die lebendige Kugel in der Hand des Spielers, die geworfen wird. Er wird **nicht** gestapelt.

**Stil:** hochwertiger, glänzender Cartoon-Look wie im ChatGPT-Konzeptbild „Wobble Scoops Character Design“ (einzige Stilreferenz, Higgsfield-Versionen verworfen) (Richtung Pixar, Slime Rancher 2, Brawl Stars). Cremig, saftige Glanzlichter, satte Farben, viel Persönlichkeit. **Nicht** matt und nicht schlicht. So nah daran, wie Roblox es mit PBR-Materialien (Color, Roughness, Normal) hergibt.

**Muss:**
- Sitzt in einer kleinen Waffel-Schale wie im Konzeptbild (Entscheidung 24.10.2026: erlaubt, weil Attack-Scoops nicht gestapelt werden). Waffel fliegt beim Wurf mit, beim Aufprall Sahne und Waffelkrümel als VFX
- Rundlich, leicht squishy, dicke glänzende Schmelztropfen unten
- Große, glänzende Streusel
- Riesige glänzende Augen mit Glanzpunkt, ausdrucksstarker Mund, rosa Wangen
- Gesicht austauschbar (Augen und Mund getrennt), damit das Emotionssystem funktioniert
- Ausdrücke: Freude, Jubel, Wut, Angst, Überraschung, Splat
- Lesbar in der Hand und im Flug

**Technisch:**
- Roblox-kompatibel (MeshPart), optimierte Polygonzahl, PBR-Texturen
- Pivot in der Mitte, Gesicht nach vorn (LookVector)
- Größe in der Hand ca. 1,2 Studs
- Spur, Spritzer, Pfützen, Sorten-Auren sind VFX, nicht Teil des Modells

**Erste Lieferung:**
1. Vanille-Attack-Scoop mit kleiner Waffel
2. Gesichter für 6 Ausdrücke, austauschbar
3. Roblox-Datei plus Texturen
4. Vorschau aus mehreren Winkeln und einmal in Roblox Studio gerendert

Sorten (Erdbeere, Minze, Chili), Animationen und Partikel separat vereinbaren.

---

## 7. Technischer Stand (Repo, geprüft 04.11.2026)

- Repo: https://github.com/Webizode/roblox. Aktueller Arbeits-Branch `feature/tower-scoops` (enthält `feature/big-swirl`), noch nicht in `claude/wobble-scoops-week1` (Standard-Branch auf GitHub) gemergt
- ca. 18.500 Zeilen Luau in `src`, Client/Server/Shared sauber getrennt, Server-Autorität
- **326 Unit-Tests bestanden, 0 fehlgeschlagen** (`lune run scripts/check` grün, 04.11.2026)
- Vorhanden: Big Swirl Launcher, Fangen, Turmphysik mit Kippen, Steady-Haltung (F) mit Energie, Sprint (Shift), Dash (Q) mit Animationen, Kampfmodus (R) mit eigener Lauf- und Idle-Animation, Eisball-Wurf mit Ladeleiste, Munition, Nachladen, Treffer stören Turmbalance, Knockdown mit Animationen, Beute (verschüttete Kugeln einsammeln), Waffel-Rucksack, Servieren am eigenen Plot, 12-Plot-Map mit Arena und Safe Zone, Teleport-Buttons, Kill-Test-Log
- **Map** (seit 30.10.2026, ersetzt Kornels Insel mit 6 Ständen): Graybox für 12 Spieler im Place (`Workspace."Ice Cream Map"`). Von innen nach außen: Arena r 0–135 um die Big Swirl (Boden y 1,2, 12 Plateaus, Deckung in `Covery`), ebener Streifen r 135–171 auf y 9 mit 12 eingelassenen Rampen (Oberkante r 159, Grenzlinie in `Strefa`), Hub-Ring r 171–232 (Deko und Wege in `Dekoracje.Hub`, siehe unten), 12 Brücken 18 × 66 (r 229–295) zu 12 Plot-Inseln 110 × 60 (Mitte r 322, seit 04.11.2026, vorher 70 × 70 mit Mitte r 327). Insel, Brücke und Rampe liegen je auf einer Linie bei 15° + k·30°. Abgerundete Optik aus dem Baukasten `assets/IceKit`, darunter unsichtbare Kollisionsquader. Einzelheiten und Map-Vertrag: `CLAUDE.md` und `MapService`
- **Arenaboden** (seit 04.11.2026, ersetzt `Arena_Baza`): Der alte Boden lag doppelt und war nicht verankert, beim Spielstart sanken beide Platten in den braunen Inselkern (`Wyspa_Kern`, Oberkante y 1,0); das war das Orange-Braun, und die Landepunkte lagen auf dem Kern. Neu in `Plac`: `Arena_Boden` (r 133, verankert, Oberkante y 1,2 wie Rampen und Deckung) mit einer gekachelten MaterialVariant `WS_ArenaPlates` (cremefarbene Platten 6 × 6 mit hellrosa Fugen, 512 px, 12 Studs je Kachel), `Arena_Rand` (r 136, rosa, 0,02 tiefer) als runder Rand, ein Emblem um die Big Swirl (Scheibe r 49 mit MaterialVariant `WS_ArenaEmblem`, ein Bild über die ganze Scheibe: Goldring, Waffelgitter, rosa Eis mit Tropfen, 1024 px, Teilefarbe #D1B4A9 als Tönung, damit Waffel und Pink auf dem Bildschirm nah an #E2782C und #F06AAE liegen) und 14 große Streusel (Kapseln 3,6 × 0,7, mindestens 22 Studs Abstand; die ersten 36 dünnen Stäbchen sahen aus der Ferne wie Fehler aus, Variante „ohne“ über `SPRINKLES = 0`). Alles gesperrt (`Locked`): ein versehentliches Ziehen in Studio hatte den Boden um 0,38 angehoben und Emblem, Streusel und Landekreise darin versenkt. Nur Boden und Rand kollidieren und werden abgefragt; Emblem und Streusel liegen darüber ohne Kollision, Landeregeln unverändert (13.347 Landepunkte). **Bilder auf Böden nur als MaterialVariant, nie als `Texture` oder `Decal`:** Roblox zeichnet diese mit einem Tiefenversatz zur Kamera, der aus flachem Spielerblick groß wird, und ein texturierter Boden verschluckt dann alles knapp darüber (Landekreise, Beute, Emblem).
- **Streifen und Hub-Ring** (seit 04.11.2026, Referenz „Bonbon-Wege für Eiscremewelten“): rosa-cremefarbenes Pflaster aus abgerundeten Steinen im Läuferverband (4 × 3 Studs), MaterialVariant `WS_Pavers` (`Wyspa_Pavers`, 512 px, 12 Studs je Kachel) auf allen sichtbaren begehbaren Teilen von `Wyspa`: `Ring` (90), `Pas.Pas_Zewn` (72), `Pas.Pas_Bok` (24), `Brzeg_01` bis `_12`. Teilefarbe #F2C2CB färbt das Bild ein; ungefärbt wirkte das Pflaster unter Sonne und Bloom weiß. Nur die Optik ist neu, Größe, Lage, Kollision und Abfragen sind unverändert, die unsichtbaren `Pas`-Blöcke bleiben, alles gesperrt. Vorher-Stand in `ServerStorage."MapBackup_2026-11-04_WyspaFloor"`, Skript `assets/ArenaKit/studio_wyspa_floor.luau`.
- **Hub-Deko und Wege** (seit 06.11.2026, freigegeben): Der Hub-Ring ist mit Hub-Kit-Modellen dekoriert, alles in `Dekoracje.Hub`, das ist für Landepunkte gesperrt und mit einem Klick ausblendbar.
  - **Wege:** Erhöhte Gehwege, 0,52 hoch, mit rundem Karamell-Bordstein. Sie führen von jeder Rampe zur Brücke, als Ring bei r 192, zu Brunnen, Hafentor und den drei Shop-Flächen und über die Wegplatten der Plots. In der Arena und auf den Rampen gibt es keine.
  - **Pro Sektor:** Vorplatz mit Laternen, Bank, Mülleimer und Blumentopf, eine Baumgruppe in den Sortenfarben, eine Kisten- und Fassgruppe.
  - **Einmalig:** Brunnen bei 180°, Hafentor „Coming Soon“ mit Wegweiser bei 300°.
  - **Shop-Flächen:** Platzhalter für Upgrade Shop (0°), Cosmetic Shop (120°) und Quest Hub (240°), dort keine Deko.
  - **Wiese** (seit 07.11.2026, erst in Sektor 1 freigegeben, dann auf alle 12, ersetzt die Grasbeete):
    - Der ganze Hub ist eine durchgehende Wiese bis an jeden Bordstein, 48 CSG-Flächen (`Sektor_XX.Rasen`), 0,08 hoch, ohne Kollision.
    - Gepflastert bleiben die Wege, die Vorplätze an den Brücken, die Shop-Flächen, Brunnen mit Café, Hafentor mit Kiosk und der Platz vor dem Pavillon.
    - Darunter liegt Terrain-Gras mit `Terrain.Decoration`, Oberfläche unter dem Pflaster. Die Halme wachsen durch den Rasen, nie auf Wegen.
    - Rasen und Terrain haben dieselbe Farbe #82B84E. Auf niedriger Grafikstufe ohne Halme sieht es also gleich aus.
    - Lose Kugeln liegen auf dem Rasen wie auf dem Pflaster.
    - Höchstens 2 Eis-Bäume je Sektor.
    - Einzelheiten stehen in `assets/HubKit/README.md`.
  - **Außenzaun:** Um den Ring läuft bei r 231 ein Zaun aus dem Plot Kit mit Karamell-Kappen und Schoko-Pfosten, also neutral. Er hat Lücken an allen 12 Brücken (22,4 breit) und am Hafentor. Unsichtbare Wände bis y 40 stehen in `Sperre.Hubzaun` und stoppen nur Spieler.
  - **Leaderboard-Platz** (seit 07.11.2026): Ein pinker Platzhalter steht vor dem Cosmetic Shop, innen am Ringweg (r 180) und zu den Brücken gedreht. Dort sehen ihn die meisten Spieler auf dem Weg vom Plot in die Arena, aus den Sektoren 11, 12 und 1. Das Modell kommt später.
  - **Füllgebäude:** Es gibt nur drei: das Café am Brunnen, den Pavillon in der Wiese von Sektor 2 und den Kiosk am Innenfeld beim Hafentor. Wände und Dach sind gedämpft, nur Markise und Schild tragen eine Sortenfarbe. Die Garage ist gebaut, steht aber nicht im Place, weil der Ring sonst zu voll wirkte.
  - **Laternen:** Das Licht ist an, mit Helligkeit 1 und Reichweite 14. Vorher waren es 2 und 18, damit wirkten die Brückenköpfe weiß.
  - **Umfang:** 329 Modelle und 2.511 Teile im Hub, davon 48 Rasenflächen. Dazu kommen 177 Sperrwände. Die ganze Map hat 7.787 Teile (Stand 07.11.2026 abends, mit Brücken und Wiese).
  - **Getestet am 07.11.2026:**
    - In allen 12 Sektoren geht man von der Rampenoberkante bis auf die Brücke (r 165 bis 249) in normalem Gehtempo, je 4,0 bis 4,2 s.
    - Teleport zu Arena und Plot funktioniert.
    - Echtes Servieren mit 3 Kugeln am ServePoint funktioniert.
    - Keine Kollision eines Modells schneidet Wege oder Shop-Flächen.
    - Keine neue Warnung.
  - Skript und Einzelheiten: `assets/HubKit/studio_hub_decor.luau` und `assets/HubKit/README.md`.
- **Holzbrücken** (seit 07.11.2026, erst `Most_01` als Test, dann alle 12): Jede Brücke ist ein Model `Mosty.Most_k.Bruecke` aus den Hub-Kit-Modulen `BridgeEnd` + 4 × `BridgeMid` + `BridgeEnd`, 66 lang von r 229 bis r 295, je 42 Teile. Holzdeck, weißes Geländer, Pfosten und Seitenbalken in Karamell (#C98A4F), nur die Pfostenkappen in der Hauptfarbe der Sorte (60/30/10). Das Deck liegt bündig auf `Pomost_Kolizja`, die Laufkollision bleibt unverändert. Das alte flache Deck `Pomost` liegt in `ServerStorage."MapBackup_2026-11-07_Pomost"`.
  - **Sperre:** Das Geländer ist 3,5 hoch. Ohne Wand kam man mit Sprung ins Wasser. Deshalb steht über jedem Geländer eine unsichtbare Wand bis y 40, von großem Pfosten zu großem Pfosten, in `Sperre.Bruecken.Most_k`. Sie stoppt nur Spieler. `studio_arena_rim.luau` behält beim Neubau jetzt `Hubzaun` und `Bruecken`.
  - **Getestet am 07.11.2026:** Auf allen 12 Brücken geht man vom Ring bis r 303 auf den Plot, Tempo nie unter 20,5. Niemand kommt über das Geländer, auch nicht mit Sprung und Power-Dash (24 Versuche auf 4 Brücken). Teleport zu Arena und Plot und echtes Servieren funktionieren. Keine neue Warnung. Das Brückenende berührt am Plot den Bordstein und den Weg der Plot-Wege (Oberkante 9,2 bis 9,5), beim Gehen ohne Hängenbleiben.
  - Skript: `assets/HubKit/studio_bridges.luau` (`BRIDGES = "all"`, `RESTORE = true` stellt das alte Deck wieder her). Module: `assets/HubKit/build_hub_pack.py`.
  - Offen: Läuft das Plot-Kit-Skript neu, liegen die Wegsteine wieder tief, dann das Hub-Skript erneut laufen lassen.
- **Kill-Test-Korrekturen (08./09.11.2026):**
  - **Plot-Gras:** Alle 12 Plots haben dieselbe Graswiese wie der Hub (#82B84E, gleiche MaterialVariant), dazu Terrain-Halme. Auf Wegen, dem runden Platz, an den Stationen, am Schild, am Zaun, am Spawn und 12 Studs um den ServePoint wachsen keine. Die Zonen-Marker `Strefy` sind ganz unsichtbar, vorher machten sie Farbflecken. Skript: `assets/ArenaKit/studio_plot_grass.luau`.
  - **Brunnen:** Das Wasser war da, aber blass (#86DDF7, 35 % durchsichtig auf weißem Becken). Jetzt ist es #4FC3F0 mit 12 % Transparenz, mit zwei Wellen-Texturen, die der Client verschiebt (`FountainWater`, Tag `ScrollingWater`). Dazu kommen Spritzer im Becken und ein sanfter Strahl oben. Skript: `assets/HubKit/studio_fountain_water.luau`, Bilder: `make_fountain_textures.py`.
  - **Plot-Schilder:** Der Name des Besitzers steht als SurfaceGui direkt auf dem Schild. Vorne steht er auf dem Cremefeld, hinten auf einer eigenen Creme-Plakette, und er schrumpft bei langen Namen. Träger sind die unsichtbaren `NamePlate_Front`/`_Back` (`assets/PlotKit/studio_plot_sign_names.luau`). Den Text setzt `PlotService`. Das schwebende BillboardGui ist nur noch die Rückfalloption.
  - **Flackern (Z-Fighting):** Gefunden mit `assets/find_zfighting.py`. Am Sell Cart lag die Abzeichen-Rückseite auf dem Goldring, an der Working Station lagen Zahnrad-Front und Scheibe sowie Eis und Schüssel aufeinander. Im Place sind `SellCart_Gold` und `WorkingStation_Gold` 0,06 nach hinten und `WorkingStation_Pink` 0,06 nach oben verschoben, auf allen 12 Plots und in den Vorlagen (Attribut `ZFightFix`). Die Quelle `build_plot_pack.py` ist korrigiert. Scoop Chest, Schild, Zaun, Wege und das Hub Kit sind sauber, bis auf Bodenflächen, die man nicht sieht.
  - **Meer bis zum Horizont:** Das Terrain-Wasser ist nur ein Quadrat von 1024 × 1024 und endete sichtbar etwa 180 Studs hinter den Plots. Jetzt legt jeder Client eine eigene flache Meeresfläche darüber (`src/client/Controllers/Ocean.luau`, Werte in `Config/Map.ocean`). Es ist ein einziges Teil von 2048 Studs, das ein SpecialMesh 24-mal so breit zeichnet (etwa 49.000 Studs). Es liegt 0,6 über dem Terrain-Wasser, rückt in 48-Stud-Schritten mit der Kamera mit und trägt eine ruhige, treibende Wellen-Textur (`assets/World/make_ocean_texture.py`). Kollision, Abfragen und Berührung sind aus, Spieler und Kugeln fallen weiter ins Terrain-Wasser darunter.
    - Verworfen: 49 Kacheln, weil Roblox weit entfernte Teile einfacher beleuchtet und an den Kachelgrenzen Helligkeitsstufen entstanden. Ebenfalls verworfen: Die Fläche nur 0,15 über dem Wasser, weil dann die Wellen des Terrain-Wassers als dunkle, wandernde Flecken durchstießen. Mehr Terrain-Wasser kam nicht in Frage: Es wird gestreamt, würde also am Streaming-Radius trotzdem enden, und auf dem Handy kostet es Speicher.
    - Atmosphere im Place: Density 0,18, Haze 1,0, Offset 0,1 (vorher 0,1 / 0,15 / 0). Das Meer geht weich in den Himmel über, die Map bleibt klar.
    - Geprüft am 09.11.2026 von oben, vom Plotrand, unter einer Brücke und auf Grafikstufe 1: keine Kante, keine Naht, die Brückenpfähle (bis y −10) und Inselsockel stehen sauber im Wasser. Auf Stufe 1 sieht man vom Plot aus die ganze Map.
  - **Streaming:** Die 12 Plots und 12 Brücken stehen auf `LevelOfDetail = StreamingMesh` (`assets/World/studio_streaming_lod.luau`). Die Map reicht bis r 400, `StreamingTargetRadius` 1024 deckt sie also von jedem Punkt aus ab.
- **Sortenfarben** (seit 06.11.2026, vorher fast nur Pink und Creme): Jeder Sektor (Plot, Rampe, Eingangsbogen, Arena-Rand vor der Rampe, Brücke) hat eine von 12 Sorten: Mint, Mango, Blaubeere, Zitrone, Lavendel, Erdbeere, Pistazie, Bubblegum, Karamell, Himmelblau, Schoko, Kirsche (Plot 01 bis 12). So erkennt man von der Arena aus den Weg zum eigenen Plot. Die Deckungen sind gemischt in allen 12 Sorten. Pfosten sind in Schoko, Inselsockel und Streifenkante in Karamell. Hub-Ring und Streifen sind Vanille-Creme statt Rosa. Es ist nur umgefärbt, die alte Farbe steht in jedem Teil im Attribut `FlavorOrigColor`. Skript und Tabelle: `assets/MapColors/`.
  - Offen: Die Ziegelwand zur Arena gibt es in Vanille (im Place) oder in Karamell, die Wahl trifft der Nutzer.
  - Für später: Die Inselsockel brauchen Struktur, etwa Waffel oder einen Schoko-Glasurrand mit Tropfen. Heute sind es glatte Karamell-Flächen.
- **Landekreise mit Kontur** (seit 04.11.2026): dunkler Ring in Berry `#633F52` um jeden Landekreis (ein Ringbild als Decal auf der Oberseite des Kreises, schrumpft mit ihm, wird mit ihm ausgeblendet), Innenfläche weniger durchsichtig (0,35 statt 0,5). Werte in `Config/TowerScoops` `landingCircle`. Getestet mit 10 Kugeln im Abstand von 0,15 s auf Platten und Emblem, bei hoher und niedrigster Grafikqualität: alle Kreise klar lesbar, Ring und Kreis verschwinden bei der Landung zusammen Bauskript `assets/ArenaKit/studio_arena_floor.luau`, Texturen `assets/ArenaKit/make_floor_textures.py`, alter Boden in `ServerStorage."MapBackup_2026-11-04_ArenaFloor"`
- **Plots** (seit 30.10.2026, ersetzt die Wagen; breite Inseln seit 04.11.2026): jeder Spieler bekommt einen der 12 Plots (`PlotService`, Spieler-Attribut `PlotName`), spawnt auf dem runden Platz seiner Insel und serviert am ServePoint vor der Theke des Sell Carts (r 331, `serveRadius` 8 Studs; bis 05.11.2026 am Brückenkopf r 298). Über dem eigenen Plot steht „YOUR PLOT“ (vorher „YOUR CART“), die Hinweise sagen „plot“ statt „cart“.
  - **Form:** Rechteck 110 breit entlang des Rings × 60 tief, Ecken mit 6 Studs Radius, die Brücke mündet mittig an der langen Innenseite (Innenkante r 292, Außenkante r 352). Lauffläche 104 × 54 mit Neon-Rand. Kleinster Abstand zwischen zwei Inseln 44,9 Studs (vorher 83,5)
  - **Anordnung** (seit 06.11.2026, Plot-Kit-Modelle, `assets/PlotKit/studio_plotkit_place.luau`), von der Brücke aus: Working Station links (u −36), Sell Cart hinten mittig (v 16, Front zur Brücke), Scoop Chest rechts (u 32), alle zum runden Platz (0, −4) gedreht. Wege von der Brücke (am Brückenkopf 18 breit) über den Platz zu allen drei Stationen. ServePoint vor der Theke (0, 9), Spawn auf dem Platz (13 Studs vom ServePoint, außerhalb des Serve-Radius). Zonen (`Config/Map.plot.zones`, Marker in `Strefy` ausgeblendet): Working Station 34, Sell Cart 36, Scoop Chest 34; Upgrades kommen auf die Hauptinsel. Zaun bei ±48 / ±24 mit 32 Studs Lücke an der Brücke. Plot-Schild „PLOT NN“ rechts neben dem Brückenkopf, zur Brücke gerichtet, darüber der Name des Besitzers. Im Playtest am 06.11.2026 geprüft: Spawn frei, Teleport „MY PLOT“ und „ARENA“, Servieren an der Theke, Zaunlücke frei. Von der Brücke aus verdeckt das Schild die Scoop Chest fast ganz
  - **Für später, tropischer Look** (Sand, Holz, Bambus, Palmen, Fruchtfarben mit Eiscreme-Bezug, als Kontrast zur Candy-Hauptinsel): Die Lauffläche ist eine eigene Schicht, ein Sandrand kann rund um die Insel dazukommen. Bis 10 Studs (`sandReserve`) bleiben die Inseln 20,4 Studs auseinander (der Test verlangt mindestens `minGap` 15)
  - Maße in `Config/Map.plot`, Lage aller Teile in `PlotLayout` (mit Tests); `MapService` warnt beim Start, wenn ServePoint, Spawn oder Schild im Place nicht dazu passen. Map vor dem Umbau: `ServerStorage."MapBackup_2026-11-04_Plots70"`
- **Arena und Safe Zone** (seit 30./31.10.2026, Safe-Zone-Turm 04.11.2026): Die Arena ist der Boden plus die Rampen bis zu ihrer Oberkante (`Config/Map.arena`, geprüft von `ArenaZone`, auf Server und Client dieselbe Funktion, eine Linie ohne Hysterese). Alles außerhalb (Streifen, Hub, Brücken, Plots) ist Safe Zone. Nur in der Arena landen Big-Swirl-Kugeln, treffen Eisbälle (auch schon fliegende) und gibt es den Kampfmodus. In der Safe Zone:
  - **Teleport:** oben mittig die Buttons „my plot“ und „arena“ und der Hinweis „SAFE ZONE“, sichtbar 0,2 s nach dem Verlassen (`displayDelay`, kein Flackern auf der Linie), immer klickbar; der Server teleportiert sofort, nur Fluten unter 0,25 s Abstand werden verworfen (`teleportMinInterval`). „arena“ landet auf der Mittellinie der eigenen Rampe knapp hinter der Oberkante (ArenaEntry), Blick zur Arena (`ArenaService`, `TeleportMenu`)
  - **Turm kippt nicht:** Er wackelt beim Laufen, Kurven und Dashen weiter, aber die Schwerkraft zieht ihn nicht weiter um (`Config/Tower` `safeGravity` 0), er richtet sich also von selbst auf. Seine Neigung stoppt bei 70 % des Kippwinkels (`safeTiltFraction`), unter der Ächz-Schwelle von 80 %: kein Ächzen, kein Kippen. Ein Turm, der beim Verlassen der Arena ächzt, wird sofort gerettet („SAVED!“) und richtet sich sanft auf, ohne Sprung (`safeEaseTime` 0,3 s). Im Playtest am 04.11.2026 (17 Kugeln): beim Verlassen 0,52 rad, nach rund 1 s unter 0,2, nach 3 s fast senkrecht; zurück in der Arena stand er weiter. Vorher blieb er draußen bei 70 % schräg stehen und kippte 0,9 s nach dem Zurückgehen ohne Eingabe. Der Client prüft die Arena selbst, der Server lehnt eine Kipp-Meldung von jemandem ab, der klar außerhalb steht (Arena plus `arena.serverSlack` 4 Studs), und schickt den Turm unverändert zurück
  - **Kampfmodus:** aus, die Maus ist frei (siehe Kampfmodus)
  - Alte Schutzzone am Wagen (`Config/Loot` `safeRadius` 14 Studs um den ServePoint, Treffer dort harmlos, Werfen hebt den Schutz auf) ist noch im Code, wirkt aber praktisch nicht mehr, weil die Plots ohnehin außerhalb der Arena liegen
- **Speichern** (seit 27.10.2026): ProfileStore mit Session-Lock. Gespeichert werden Coins, Upgrade-Stufen, servierte Kugeln pro Sorte, Kugeln gesamt, Rekord-Turm und die Einstellungen. Datenformat Version 2 mit Migration, alte Spielstände bekommen Standard-Einstellungen. Studio speichert getrennt, `/resetsave` setzt in Studio zurück
- **Einstellungsmenü** (seit 28.10.2026): Zahnrad oben links, am Gamepad Steuerkreuz hoch. Audio (Effekte, Musik), Grafik (VFX-Qualität, Leistungsmodus ohne Schatten, Bloom, Sonnenstrahlen), Kamera (Wackeln, Sichtfeld 70–110, Standard 80, Sprint-/Dash-/Ziel-Effekte), Fadenkreuz (Form, Größe, Farbe), Steuerung (Eingabegerät, Tastenübersicht im Kampf). Server prüft jeden Wert und speichert höchstens einmal pro Sekunde. Hintergrundmusik ist ein Platzhalter
- **Big Swirl** (seit 28.10.2026, Branch `feature/big-swirl`): neues Cartoon-Modell aus Blender (`assets/BigSwirl`, Skripte für Bau, Animation und Export, ca. 19.200 Dreiecke), Ø 52 Studs mit begehbarem Sockel, Treppen und Trog mit Eismischung. `MapService` setzt sie beim Start auf den Marker `Plac.Arena_Znacznik` in der Arenamitte. Sechs Arme schöpfen aus dem Trog und schießen; jede Kugel kommt aus dem freien Arm, der in ihre Richtung zeigt, ein Arm wird erst nach seinem kompletten Zyklus wieder benutzt. Die Bewegung ist der in Blender animierte Zyklus (`Config/BigSwirlCycle`), jeder Client dreht damit die Bones selbst nach der Server-Uhr, ohne Animations-Assets. Die Kugel liegt ab dem Schöpfen sichtbar (1,8-fach) im Becher und schrumpft nach dem Abschuss; der Landekreis erscheint dadurch rund 2,3 s früher
- **Turm-Kugeln** (seit 29.10.2026): eigenes Modell statt der schlichten Kugel, erste Sorte Vanilla (Kuppel, Tropfrand mit 7 Lappen, hohle Unterseite zum Stapeln, Vanille-Punkte als Detailbild). Nah 448 Dreiecke, ab ca. 40 Studs die Fern-Version mit 112, getauscht vom Client. Ein Umriss-Highlight pro Turm in der Farbe der Big Swirl, rot beim Ächzen. Im Flug dreht sich die Kugel beim Steigen und kippt nach dem höchsten Punkt wie ein Federball mit der Kuppel nach unten; gefangen schwingt sie aufrecht und plumpst auf den Turm (die neue oberste Kugel fällt 0,7 Studs und staucht sich kurz). Dahinter eine kurze Spur in der Sortenfarbe, bei seltenen Sorten länger und heller, bei den seltensten mit Funken, kürzer bei niedriger VFX-Qualität und im Leistungsmodus. Nur Optik, die Flugbahn bleibt die des Servers. Werte in `Config/TowerScoops`, Logik in `ScoopFlight` (mit Tests), Modelle unter `ReplicatedStorage.TowerScoops` (Asset-Skripte und Ablauf: `assets/TowerScoops`, Art Bible). Sorten ohne Modell zeichnen weiter die schlichte Kugel
- **Sorten** (seit 29.10.2026): nur die 11 Common-Sorten (Familie Classic, Werte und Physik wie Vanilla, Gewicht je 10): Vanilla, Chocolate, Strawberry, Mint, Lemon, Bubblegum, Cookie, Pistachio, Mango, Stracciatella, Watermelon, alle mit eigenem Turm-Kugel-Modell. Feld `rarity` in `Config/Flavors` (common bis legendary, Farben in `rarityColors`). Die bisherigen seltenen Sorten (Rocky Road, Cookie Dough, Mochi, Jelly, Chili Lava, Cursed Pickle) sind am 29.10.2026 entfernt, ebenso die Rezepte, die sie brauchten (Secret Stacks Rocky Mountain und Pickle Party, Swirls Cookie Crunch, Rocky Mochi, Mint Jelly Fizz, Spicy Pickle). Es bleiben Neapolitan, Berry Swirl und Choco-Mint Twist. Die Familien heavy, sticky und wild bleiben für die neuen Sorten; die Physik-Tests nutzen dafür Test-Sorten
- **Liegengebliebene Kugeln** (seit 29.10.2026): Eine Kugel aus der Big Swirl, die niemand fängt, bleibt 3 s am Landepunkt liegen (`Config/Loot` `landedLifetime`), jeder darf sie aufheben, in der letzten Sekunde blinkt sie (`landedBlinkSeconds`), dann verpufft sie. Der Server entscheidet (`LootService.landed`, eigenes Limit `maxLanded`, verdrängt keine verschütteten Kugeln). Im Wasser ist sie sofort weg. Verschüttete Kugeln bleiben 10 s liegen (`lifetime`, seit 29.10.2026, vorher 15 s und davor 12 s), blinken in der letzten Sekunde (`blinkSeconds`) und verpuffen dann wie die liegengebliebenen; ein Client, der die Entfernung verpasst, räumt sie nach `expireGrace` selbst ab. Bei vollem Cone zeigt die Turm-Anzeige „36/36 FULL“, die Kugel bleibt liegen und ein Hinweis „CONE FULL!“ erscheint (höchstens alle `fullNotice` s)
- **Namensschild** (seit 29.10.2026): über fliegenden und liegenden Kugeln „Name (Wert [Münze])“, Name in der Farbe der Seltenheit (`Config/Flavors` `rarityColors`), Münze wie im HUD (`Ui.coinIcon`), sichtbar bis 40 Studs (`Config/TowerScoops` `label`). Golden zeigt den Wert ×5 (`Config/Economy` `goldenMultiplier`), sobald der Launcher goldene Kugeln schickt. Nicht über Turm-Kugeln und nicht über der Wurfkugel
- **Zielwahl der Big Swirl** (seit 29.10.2026, an die 12-Plot-Map angepasst am 30.10.2026): Alle Kugeln landen in der Arena (Landepunkte nur bis r 135, `landingRadius`, nie auf der Deckung `Covery`, nur Stellen, auf denen man stehen kann). Etwa 80 % landen an einem zufälligen Punkt, zur Mitte hin gewichtet (`randomBands`: 35 % bei r 25–55, 35 % bei 55–80, 30 % bei 80–100, also höchstens rund 75 % des Arenaradius; der äußere Ring und die Rampen bleiben der Weg hinaus). Der Rest (`nearPlayerShare` 0,2) landet bis 9 Studs neben einem Spieler, der in der Arena ist und sich bewegt. Wer sich 4 s lang nicht mehr als 2 Studs bewegt (`idleSeconds`, `idleRadius`), bekommt keine Kugeln gezielt. Die 3 Tutorial-Schüsse für neue Spieler kommen, sobald sie in der Arena sind. Werte in `Config/Launcher`, Regeln in `TargetRules` und `MapRules` (mit Tests)
- **Kampfmodus** (Maus seit 29.10.2026, nur in der Arena seit 31.10.2026, Variante a): R schaltet den Kampfmodus nur in der Arena ein, außerhalb kommt „Combat mode only in the arena“. Wer die Arena verlässt, fällt automatisch heraus („Combat mode off: safe zone“), und die Maus ist dort frei für die Teleport-Buttons. Im Kampfmodus bleibt der Mauszeiger versteckt und in der Mitte gesperrt, auch bei gehaltenem Rechtsklick (der geht dann nicht an Roblox' Kamera). Der Server prüft dieselben Regeln (`MouseRules`, mit Tests) mit `arena.serverSlack` (4 Studs) Toleranz. Im Playtest am 04.11.2026 geprüft: R in der Arena sperrt die Maus, zu Fuß über die Rampe hinaus endet der Modus und die Teleport-Buttons erscheinen, R draußen bleibt aus
- **Animationen** (R15, eingetragen in den Configs, Längen im Playtest am 04.11.2026 geprüft):
  - Wurf `R15_WS_Throw` (seit 30.10.2026, `rbxassetid://122799230007876`, 0,73 s): eine Animation mit Ausholen und Wurf, Marker „Held“ bei 0 s, „Release“ bei 0,033 s (`Config/Combat` `throwAnimation.throw`, `throwRelease`). Beim Halten bleibt sie in der Held-Pose, nach dem Loslassen schwingt sie durch, sodass die Kugel die Hand verlässt, wenn der Server sie startet. Die Kampf-Haltung davor ist weiter prozedural (`ThrowAnimator`)
  - Treffer, Knockdown, Aufstehen von Ismo (seit 30.10.2026, `Config/Combat` `reactionAnimations`). Zugeordnet nach ihrer Länge: Hit `84454561261662` (0,45 s, nur Oberkörper, Priorität Action2, Gehen und Zielen laufen darunter weiter), Knockdown `127621446568262` (0,333 s, bleibt 0,2 s auf dem letzten Bild liegen), GetUp `127552978582776` (1,367 s, 1,25-fach abgespielt, 0,25 s eingeblendet, 0,2 s Ausblenden in Idle), Knockdown und GetUp auf Action4. Die Knockdown-Dauer passt dazu: `knockdownTime` 1,63 s = 0,333 + 0,2 + 1,367 / 1,25 (Test in `Combat.spec`). Laden sie nicht, springt die prozedurale Pose ein
  - Dash (seit 31.10.2026, `Config/Movement` `dashAnimations`): vorwärts, rückwärts, links, rechts (vorwärts bisher nur eine Animation). Die Animationen sind 1 s lang und werden so beschleunigt, dass sie 0,1 s nach dem Dash enden (`dashAnimationRecovery`, `Dash.animationSpeed`); die prozedurale Neigung nur noch für Richtungen ohne Animation
- **Fadenkreuz und Perfect Timing** (seit 29.10.2026): Ein sauberer dünner Kreis, fest in der Bildschirmmitte (fest weiß, grün bei Perfect; seit 29.10.2026 keine Fadenkreuz-Einstellungen mehr, alte gespeicherte Werte werden ignoriert). Der Wurf zielt durch die Mitte; eigener Charakter, eigener Turm, Kugeln und Beute (`LocalVisuals`) stören weder das Zielen noch die Kamera. Der Kreis wird größer beim Gehen, Sprint, nach einem Dash und direkt nach dem Wurf und beim Halten etwas kleiner, nur Anzeige, keine Streuung (`AimRules`). Antippen wirft sofort (Stärke 0: 55 Studs/s, Trefferstärke ×0,6); Halten hebt die Stärke in 0,5 s auf 1 (90 Studs/s, ×1). Beim Halten pendelt ein innerer Kreis von der Mitte zum Außenkreis und zurück (`Combat.pulse`); wenn er den Außenkreis berührt (±0,06 s), wird alles grün, und Loslassen ist ein Perfect-Wurf: 110 Studs/s, gleiche Trefferstärke, eigener Sound, goldener Schweif für alle. Der Server prüft Stärke und Perfect mit seiner eigenen Haltezeit (±0,08 s). Der Wurf zielt immer genau durch die Mitte. Werte in `Config/Combat` (`perfect`, `crosshair`, `aimAssist`)
- **Treffer-Feedback** (seit 29.10.2026): rotes X am Kreis bei eigenem Treffer, rote Zahl der verlorenen Kugeln über dem Getroffenen, Feed mittig unten „YOU KNOCKED DOWN Name“ (eigener Treffer wirft um) und „YOU TOPPLED Name (+X)“ (Turm kippt höchstens 4 s nach dem eigenen Treffer, `feedback.creditSeconds`). Der Server ordnet zu (`CombatService.toppled`, Remote `HitFeedback`)
- **Knockdown-Fix** (seit 29.10.2026): Treffer zählten fast immer als Streifschuss, weil der Server als Abstand zur Körperachse den Punkt nahm, an dem der Ball in die Trefferzone eintrat (immer am Rand, ca. 2,4 von 2,8 Studs). Jetzt zählt die nächste Stelle der Flugbahn durch den Körper (`Combat.passDistance`). Dazu baut sich das Taumeln langsamer ab (`staggerDecay` 0,2 statt 0,6). Ergebnis, im Test mit 2 Spielern gemessen: zwei voll gehaltene Treffer auf die Mitte werfen um (Stärke 1,00 je Treffer), drei mittige Antipper ebenfalls beim dritten (0,60 je Treffer); ein einzelner Treffer, zwei Antipper oder seitliche Antipper nicht. Jeder Treffer wird mit `Features.debugThrow` auf dem Server protokolliert (Stärke, Abstand, Tempo, Taumeln)
- **Knockdown-Punkte und Headshots** (seit 31.10.2026, ersetzt das Taumeln aus dem Knockdown-Fix): Jeder Treffer gibt Punkte nach seiner Art, bei 6 Punkten fällt man um. Normal 2, Streifschuss (normaler Treffer mit Stärke unter 0,4) 1, Perfect 3, Headshot 3, Perfect-Headshot 6 (also allein ein Knockdown). Nach 4 s ohne Treffer fällt der Zähler auf 0. Treffer innerhalb von 0,25 s (mehrere Spieler gleichzeitig) zählen nur einmal, der stärkste; die schwächeren schubsen und stoßen den Turm trotzdem. Nach dem Aufstehen 2 s Schutz: Treffer geben keine Punkte, Rückstoß und Turm-Stoß bleiben. Headshot: nur der Kopf zählt (Kopfzone = Kopfradius × 1,3, die Kugelmitte muss auf Kopfhöhe sein, ein Brusttreffer, der das Kinn streift, zählt als Körpertreffer). Der Server verfolgt die Flugbahn durch den Körper; trifft sie zuerst eine aufrechte Säule hinter dem Kopf (so hoch wie der Turm), ist es ein normaler Treffer, der Turm schützt also den Kopf von hinten. Die Stärke (`Combat.hitPower`) bestimmt weiter Rückstoß, Turm-Stoß und Haltungs-Verbrauch; der Treffer, der umwirft, stößt den Turm weiter ×1,5 (`knockdownBoost`), auch beim Perfect-Headshot (bewusst so gelassen, wird getestet). Die Zielhilfe zieht zur Brustmitte (`aimAssist.aimHeight` 0,2 statt 1,0, das war der Hals), nie zum Kopf. Sichtbares Aufladen: Die Kugel in der Hand leuchtet beim Aufladen für alle, im Perfect-Moment hell grün, mit Sound für Spieler bis 60 Studs. Feedback: eigene Knockdown-Anzeige (6 Segmente unter dem Fadenkreuz, mint mit „PROTECTED“ im Schutz), Headshot mit eigenem Sound, goldenem großem X und „HEADSHOT!“; Kill-Feed unverändert. Werte in `Config/Combat` (`knock`, `headZoneScale`, `towerBack`/`towerUp`/`towerRadius`, `held.charge`, `feedback.headshotMark`, `feedback.meter`), Logik in `HitPoints` und `Combat.isHeadshot` (mit Tests für alle Kombinationen). Sounds sind Platzhalter aus dem Creator Store
- **Nachladen Kugel für Kugel** (seit 31.10.2026, Bugfix): Vorher lud erst nach, wenn alle 3 Kugeln geworfen waren; wer 1 oder 2 warf, blieb bei 2 bzw. 1. Jetzt laden die Kugeln einzeln nacheinander nach, sobald weniger als 3 da sind: 1,4 s je Kugel (`reloadPerBall`, von leer auf voll 4,2 s). Jeder Wurf lässt das Nachladen 0,5 s warten (`reloadDelay`), eine halb geladene Kugel fängt dabei von vorn an. Der Server zählt die Kugeln (`Combat.tryThrow`, `Combat.refresh`) und lädt jede zu ihrer Zeit; ohne geladene Kugel kein Wurf. HUD: Der Kreis der Kugel, die gerade lädt, füllt sich von unten
- **Kamera-Empfindlichkeit** (seit 29.10.2026): im Einstellungsmenü unter Steuerung getrennt für Maus, Touch und Controller, 30–300 %, Standard 100 %, gespeichert und vom Server geprüft wie die anderen Einstellungen. Wirkt nur im Kampfmodus; die Kampfkamera dreht dafür jetzt auch auf Touch selbst (Wischen außerhalb von Schaltflächen). Außerhalb dreht Roblox' Kamera mit Roblox' eigener Einstellung
- **Zielhilfe** (seit 29.10.2026): in der Kampfkamera, Stärke nach dem gerade benutzten Gerät: Maus kaum spürbar, Controller mittel, Touch deutlich. Ist ein Gegner nah am Fadenkreuz (bis 8°, bis 120 Studs, sichtbar, nicht in der alten Schutzzone an seinem Plot), dreht die Kamera dort langsamer und zieht sanft zu ihm hin; beides wird zum Rand hin schwächer, kein Einrasten, niemand hinter oder neben dem Fadenkreuz. Der Server prüft Treffer wie bisher. Werte in `Config/Combat` `aimAssist`, Logik in `AimRules`
- **Musik-Playlist** (seit 29.10.2026): 3 bis 5 Lieder in zufälliger Reihenfolge, nie dasselbe zweimal hintereinander, dazwischen 60 bis 120 s Stille (`Config/Settings` `music`: `tracks`, `pauseMin`, `pauseMax`; Logik `MusicPlaylist`). Der Musik-Regler gilt für alle Lieder. Bis die Audio-IDs des Nutzers da sind: „Happyland“ als Platzhalter, leere Einträge werden übersprungen
- **Sperrzeit für verschüttete Kugeln** (seit 29.10.2026): Niemand hebt sofort auf. Der Besitzer darf nach 2 s (`Config/Loot` `ownerLock`), alle anderen nach 3 s (`ownerSeconds`, nach einem Knockdown des Besitzers ab dem Aufstehen). Die Kugeln rollen 4 bis 8 Studs weit (vorher 2 bis 4). Wird eine Kugel für einen Spieler aufhebbar, ploppt sie kurz und ein heller Ring blitzt. Der Server entscheidet (`Loot.canCollect`)
- Offen (UI): Ein Designer baut das neue Hauptmenü und Einstellungsmenü. Mit seiner Datei wird das Menü neu gebaut (Design übernehmen, Script sauberer und flüssiger, alle Funktionen des alten Menüs). Bis dahin am Menü nichts umbauen
- Offen (Sorten): eigene seltenere Sorten des Nutzers (uncommon bis legendary) entwerfen, bauen und hinzufügen, mit eigener Form, Werten, Physik und Rezepten; dazu Golden. Die goldene Spur mit Glitzer ist fertig, der Launcher meldet goldene Kugeln aber erst mit `Features.goldenScoops`
- Hinweis Spielstand: Alte Spielstände können noch servierte Kugeln der entfernten Sorten enthalten (`flavorServes`). Sie bleiben gültig; ein späteres Sammelbuch muss unbekannte IDs überspringen
- Fehlt: Golden Glow, Emotionssystem, Sorten-Fähigkeiten, Events, Upgrade-Kauf (Shop), Sammelbuch, Cone Rank, Block/Dodge. Shop und Sammelbuch kommen erst nach der Big Swirl, mit einem komplett neuen Konzept; die alten Entwürfe sind verworfen (Branches am 29.10.2026 gelöscht)
- Offene Punkte im Code: `debugCatch`, `debugThrow`, `debugDash` noch an; kleiner Exploit beim Steady-Bonus; Einstellungen, die vor dem Laden des Spielstands geändert werden, gehen verloren
- Offen (Code, gefunden im Playtest am 04.11.2026): Der Studio-Avatar hat als Gelenke `AnimationConstraint` statt `Motor6D`. `ThrowAnimator` findet deshalb keine Gelenke für die prozedurale Kampf-Haltung („no throw pose“ in der Konsole); die Wurfanimation selbst läuft. Prüfen, ob echte Spieler-Avatare das auch haben
- Offen (Design): Seit dem Treffer-Tuning vom 25.10.2026 kippen drei schnelle volle Treffer auch den kleinsten Turm
- Später (Design): Treffer in die Turmspitze hoher Türme. Heute trifft eine Kugel nur die Körper-Kapsel (bis etwa 5,4 Studs über der Hüfte); was ein hoher Turm darüber hinausragt, wird durchflogen. Klären, ob die Spitze ein eigenes Ziel wird (nur Turm-Stoß, keine Knockdown-Punkte?)
- Offen (Design): Feuerrate der Big Swirl bleibt vorerst bei 1,5 s Grundtakt (`Config/Launcher.baseInterval`, mit mehr Spielern heute schon schneller: geteilt durch die Wurzel der Spielerzahl, höchstens alle 0,45 s). Mit der größeren Map neu an die Spielerzahl koppeln; die sechs Arme schaffen eine Kugel alle 0,5 s ohne schneller zu laufen

---

## 8. Reihenfolge

1. Lokalen Stand pushen
2. **Kill-Test** mit 2–3 Spielern gleichzeitig
3. Beute: verschüttete Kugeln anderer einsammeln (erledigt)
4. Golden Glow für große Türme
5. Emotionssystem mit Vanille
6. Erdbeere, Minze, Chili
7. Events
8. Speichern, Sammelbuch, Upgrades
9. Polish, UI, Monetarisierung (nur Kosmetik)

**Kill-Test bestanden, wenn:**
- Abschießen eines großen Turms sich gut anfühlt
- mind. 8 von 10 Stürzen sich fair oder selbstverschuldet anfühlen
- mind. 3 von 5 Testern freiwillig weiterspielen
- Tester das Spiel mit Verben wie „abschießen, stapeln, retten“ beschreiben

---

## 9. Team und Budget

- Budget ca. 150 € pro Monat, kleine klar abgegrenzte Aufgaben
- Vor jedem Auftrag schriftlich: Umfang, Lieferung, Zeitrahmen, Preis
- Kein Revenue Share ohne schriftliche Regeln
- **Bis zum bestandenen Kill-Test:** keine größeren Aufträge für Modelle, UI oder Animation
- Kontakte: Spooky Doggn Dog (3D, minderjährig, fragt nach Geschenkkarten: lieber nachvollziehbar über Robux/Roblox-Gruppe, klein anfangen, schriftlich festhalten), Kareem_op und Riccc (UI, später), Nick/Nik (Animation/VFX), Apex_pro45 (Generalist, Portfolio fehlt)

---

## 10. Arbeitsregeln für Claude Code

- Erst bestehende Architektur prüfen, dann gezielt ändern
- Funktionierende Systeme nicht ersetzen
- Keine automatischen Commits
- `lune run scripts/check` muss grün bleiben
- Neue Werte in die Configs, nicht hart in den Code

---

## 11. Ideen für später

Der Ideen-Pool steht in `docs/ideen.md` (geplant, Idee, offen). Dort ist nichts beschlossen; was gebaut wird, steht hier.
