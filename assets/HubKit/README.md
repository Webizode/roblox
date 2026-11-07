# Hub Kit

Die Deko für den Hub-Ring (r 171–232) im Eiscreme-Stil der Referenzbilder, gebaut am 06.11.2026 wie das Plot Kit aus den Bausteinen und Farben des Arena-Kits (`assets/ArenaKit/arenakit.py`): glänzender Cartoon-Stil, runde Kanten, Farbe als Variante, keine Texturen. Noch nicht in Studio importiert, kein Place geändert.

- Blender-Datei: `assets/HubKit/HubKit.blend` (je Modell eine Collection `HK_<Model>`, dazu `HK_Preview` nur für die Bilder)
- Skripte:
  - `hubkit.py`: Kit, R15-Figur, Vorschau, Export. Abgeleitet von `plotkit.py`, mit den zusätzlichen Farben.
  - `build_hub_pack.py`: die Modelle, die Vorschau mit Varianten und der Generator für das Studio-Skript.
  - `run_hubkit.py`: macht alles im Hintergrund-Blender.
  - `studio_hubkit_templates.luau`: macht in Studio Vorlagen aus dem Import. Die Datei wird **erzeugt**, Änderungen gehören in `build_hub_pack.py`.
- FBX: `assets/HubKit/fbx/HubKit_<Model>.fbx`, ein FBX pro Modell
- Vorschauen: `assets/HubKit/previews/<Model>.png` und im Vault `Wobble Scoops\Hub Kit Vorschau\`. Jedes Bild zeigt von links nach rechts vorne, schräg und oben, mit derselben R15-Figur wie im Plot Kit (5,2 Studs, Waffel-Rucksack, Turm aus 20 Kugeln). Bei Eisbaum, Fass und Kiste stehen die Farbvarianten daneben.
- Maße und Daten maschinenlesbar: `assets/HubKit/hubkit_models.json`

Neu bauen (Blender muss nicht offen sein):
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/HubKit/run_hubkit.py -- IceTree Lantern
```
Ohne Namen baut es alle 13 Modelle. Jeder Lauf schreibt die FBX, die Vorschau, die JSON und das Studio-Skript neu.

## Regeln (wie im Plot Kit)

- 1 Blender-Einheit = 1 Stud, Größen an der R15-Figur (5,2) und an den Maßangaben der Referenzbögen.
- Drehpunkt unten mittig (0, 0, 0). Die Vorderseite ist in Blender −Y, in Roblox −Z.
- Pro Farbe ein Mesh `<Model>_<Farbe>`. Teile, die Studio getrennt behandelt, heißen `<Model>_<Teil>_<Farbe>`:
  - `Crown`, `Body`, `Frame`, `Panel` werden für die Varianten umgefärbt.
  - `Arrow1` bis `Arrow3` sind die Schildflächen am Wegweiser.
- Neue Farben über die Arena-Palette hinaus:
  - `Leaf` #86C94B und `LeafDark` #55A13C für Blätter, Busch, Moos und Gras
  - `Rock` #A99CC0 für die Felsen
  - `Choco` #7A4528 für die Schoko-Variante, die Mülleimer-Öffnung und das Schlüsselloch
  - `Wood` #C9783C für Bretter
  - `Lamp` #FFD66E für das Laternenglas
  - `Water` #86DDF7 für das Brunnenwasser
  - aus dem Plot Kit übernommen: `Stone` (Pflaster) und `Glass`

## Modelle

Maße in Studs: Breite (X) × Tiefe (Z) × Höhe (Y), so wie sie in Roblox stehen. Dreiecke wie exportiert, mit angewandten Modifiern. Die Kollision ist eine unsichtbare Box oder ein unsichtbarer Zylinder (Größe in der JSON und im Studio-Skript).

| Modell | Referenz | Maße | Dreiecke | Kollision | Extras |
|---|---|---|---|---|---|
| IceTree | Erdbeer-Eisbaum – Konzeptübersicht | 12,9 × 12,1 × 19,0 | 7.436 | Zylinder am Stamm (Ø 4,0, 12 hoch) | Varianten `IceTree` (pink), `IceTree_Blue`, `IceTree_Choco` |
| FlowerBush | Wobble Scoops Blumenbusch Asset-Sheet | 7,8 × 6,5 × 4,8 | 5.308 | Box 6,6 × 5,6 × 4,3 | – |
| Rock | Stilisierte Felsformation mit Gras und Blumen | 9,6 × 5,1 × 5,4 | 3.072 | 5 Boxen, eine je großem Stein | – |
| Lantern | Glänzende Eiscreme-Straßenlaterne | 6,0 × 4,3 × 12,6 | 7.156 | Sockel-Zylinder und Mast-Zylinder | Glas `Lantern_Lamp`: Neon und PointLight |
| WafflePlanter | Glänzender Waffelblumen-Übertopf | 4,9 × 5,1 × 4,7 | 5.256 | Zylinder Ø 4,5, 2,9 hoch | – |
| ParkBench | Wobble Scoops Parkbank – Asset-Übersicht | 8,7 × 3,4 × 6,3 | 3.304 | 4 Boxen (Sitz, Lehne, Armlehnen) | 2 Seats, Sitzfläche auf 1,9 |
| PicnicTable | Pastellfarbener Park mit Bank und Picknicktisch | 9,2 × 9,6 × 9,3 | 3.408 | Tisch-Zylinder und 3 Hocker-Zylinder | 3 Seats auf 1,95, zum Tisch gedreht |
| TrashBin | Verspielter Eiscreme-Mülleimer | 4,7 × 4,2 × 6,3 | 4.640 | Zylinder Ø 3,6, 5,2 hoch | – |
| Signpost | Verspielter Eiscreme-Wegweiser im Cartoon-Stil | 7,0 × 5,2 × 13,0 | 6.478 | Zylinder am Mast | 3 Pfeile als eigene Teile, je mit SurfaceGui „SHOP“, „UPGRADES“, „ISLANDS“ |
| Fountain | Verspielter Eiscreme-Brunnen mit Wasserfontänen | 16,2 × 16,2 × 9,1 | 8.988 | 3 Zylinder (Becken 2,4 hoch, Schale, Spitze) | Wasser `Fountain_Water` durchsichtig |
| Barrel | Verspielte Eiscreme-Fässer und Kisten | 3,0 × 3,3 × 3,3 | 1.252 | Zylinder Ø 2,9 | Varianten `Barrel` (Holz), `Barrel_Pink`, `Barrel_Blue` |
| Crate | dieselbe | 3,3 × 3,3 × 3,0 (Kasten 3 × 3 × 3) | 1.780 | Box 3 × 3 × 3 | Varianten `Crate` (Holz), `Crate_Pink`, `Crate_Blue` |
| HarborGate | Wobble Scoops_ Gesperrter Süßigkeitenhafen | 26,7 × 2,5 × 14,4 | 9.064 | Tor-Box 17 × 9 × 1,6 und zwei Seitenzaun-Boxen | Schrift „COMING SOON“ als Geometrie |

### Details je Modell

- **IceTree:**
  - Stamm (seit 06.11.2026 doppelt so lang, 11,6): Waffelstamm, unten breit (Ø 4) und nach oben schlanker (Ø 2,7), damit er wie ein Baum wirkt und nicht wie eine Eistüte.
  - Krone (`IceTree_Crown_Pink`): drei überlappende glasierte Kugeln wie im Referenzbild, jede mit langen Tropfen und Streuseln. Die zwei vorderen sind größer und tiefer, die hintere kleiner und höher. Oben in der Mitte sitzen Sahnehaube und Erdbeere.
  - Unter der Krone ist an der Mitte etwa 9,7 Platz. Die Tropfen hängen bis etwa 8,5 herunter. Die Kollision gibt es nur am Stamm.
- **FlowerBush:**
  - Kugelbusch in zwei Grüntönen mit Blättern.
  - 7 Blüten in Pink und Weiß, dazu zwei Kiesel.
  - Die Kollision ist eine Box, aus den Maßen gerechnet (85 %).
- **Rock:** fünf facettierte Steine, zwei davon mit Moos, dazu Kiesel, Grasbüschel und zwei Gänseblümchen.
- **Lantern:**
  - Unten: Pflasterring, Sahnekugel mit Pink-Glasur, Waffelmast mit Ringen. Oben: eine Kugel auf einem Waffelbecher.
  - Der goldene Arm reicht 2,75 aus der Mastmitte, die Laterne hängt mit ihrem Fuß auf 6,4.
  - Arm und Laterne zeigen in Blender nach +X, in Roblox nach −X, also von vorne gesehen nach rechts.
  - Das Glas ist ein eigenes Mesh in der Farbe `Lamp`. Studio macht es Neon und setzt eine PointLight hinein: Helligkeit 2, Reichweite 18, warmes Gelb, ohne Schatten.
- **WafflePlanter:** Waffeltopf auf Pflaster, Pink-Glasurrand mit Tropfen und Streuseln, Blättermound, ein großer pinker und ein blauer Hibiskus, drei Gänseblümchen.
- **ParkBench:**
  - Waffelbeine mit Gittermuster, Armlehnen mit Creme-Glasur und Streuseln.
  - Drei Sitzbretter, Oberkante auf 1,9. Die Lehne hat drei Bretter, oben sitzt das Eis-Medaillon.
  - Zwei Seats bei x ±1,6, Blick nach vorne.
- **PicnicTable:**
  - Runder Holztisch auf 2,7, Schirm in 8 Bahnen Pink und Creme. Die Kante liegt auf 7,4, der Schirm hat Ø 8,8.
  - Drei Hocker mit Pink-Kissen, Seats auf 1,95 zum Tisch gedreht.
- **TrashBin:**
  - Waffelbecher auf Pflaster mit Pink-Glasurkragen.
  - Darauf ein Creme-Deckel mit dunkler Öffnung vorne (`TrashBin_Choco`) und eine Kirsche.
  - Vorne ein Pink-Schild mit Mülleimer-Symbol.
- **Signpost:**
  - Grashügel mit Steinen und Blumen, Waffelmast, oben eine glasierte Kugel.
  - Drei Pfeile in Pink, Blau und Gold auf 9,1, 7,3 und 5,5, je 6,4 lang und 1,5 hoch, mit Creme-Glasur am Ende.
  - **Schrift** je Pfeil: Das Template-Skript setzt in jeden Pfeil-MeshPart eine SurfaceGui `Sign` (Face = Front, 60 Pixel je Stud) mit einem TextLabel `Word`: oben „SHOP“, Mitte „UPGRADES“, unten „ISLANDS“. Die Schrift ist weiß in FredokaOne mit Schoko-Rand und passt sich der Fläche an. Die Fläche ist 4 × 0,84 groß und liegt zwischen der Creme-Glasur und der Goldniete. Sie steht als Bruchteil der Pfeilfront in `SIGNS` und kommt aus `SIGN_TEXT` in `build_hub_pack.py`. Andere Wörter gehören dort hinein, danach das Skript neu laufen lassen. In Studio lässt sich auch einfach `Word.Text` ändern.
  - Alle Pfeile zeigen nach rechts. Um sie in andere Richtungen zeigen zu lassen, die Pfeil-MeshParts in Studio um die Mastachse drehen.
- **Fountain:**
  - Stufe, Mauerring aus 16 Creme-Fliesen mit abwechselnd pinken und cremefarbenen Deckplatten.
  - Vorne eine Plakette mit Eis-Symbol, im Becken Wasser.
  - Darüber Sockel und Schale mit Pink-Glasurrand und Wasser, ein Waffelkegel mit glasierter Kugel und Kirsche.
  - 6 + 6 Wasserbögen mit Schaum. Das Wasser wird in Studio mit Transparenz 0,35 eingestellt.
- **Barrel:** bauchiges Fass mit 16 Dauben, zwei Creme-Reifen und Medaillon. Der Körper (`Barrel_Body_Wood`) wird für die Varianten umgefärbt.
- **Crate:** Holzrahmen mit X-Streben auf vier Seiten und oben, Goldnieten. Rahmen (`Crate_Frame_Wood`) und Füllung (`Crate_Panel_Waffle`): Für die Varianten wird nur der Rahmen umgefärbt, Pink oder Blau. Die Waffel-Füllung bleibt bei allen drei, die Seitenwände sind also überall geschlossen. Bis 06.11.2026 war die Füllung der Varianten Creme, dann sahen die Kisten hohl aus und man sah nur den Rahmen.
  - Andere Größen wie in der Referenz: in Studio das ganze Model skalieren (`Model:ScaleTo`).
- **HarborGate:**
  - Zwei Holzpfosten mit Pink-Bändern und Creme-Kugeln. Dazwischen zwei Bogentüren, 12,8 breit und in der Mitte 7,8 hoch, mit Creme-Rahmen, zwei Pink-Bändern und goldenem Vorhängeschloss.
  - Darüber das Pink-Schild „COMING SOON“ (Schrift in Creme, als Mesh) mit Medaillon.
  - Außen zwei Fahnenmasten mit Wimpeln und je ein Seilzaun bis zu einem niedrigen Pfosten bei ±12,6.
  - Die Kollision schließt Tor und Seitenzäune, es kommt niemand durch.

## Verbesserungsrunden (höchstens zwei pro Modell)

| Modell | Runde 1 | Runde 2 |
|---|---|---|
| IceTree (Umbau 06.11.2026) | drei Kugeln verschieden groß und hoch, damit man von vorn drei Kugeln sieht und keinen flachen Hut; Tropfen länger; Stamm unten breit und oben schlank statt umgekehrt (sah aus wie eine Eistüte) | – |
| Rock | großer Stein auf volle Höhe (5,4 statt 3,9), schärfere Facetten, Moos mit mehr Tropfen | Moos flacher und breiter |
| FlowerBush | Blüten 1,5-mal so groß | – |
| Barrel | stärkerer Bauch, schmalere Enden (sah aus wie ein Eimer) | – |
| Crate | Rahmen 0,5 statt 0,42, Streben 0,6 statt 0,36 breit | – |
| HarborGate | Medaillon vor das Schild gesetzt (war fast verdeckt) | – |
| alle anderen | keine nötig | – |

## Was offen bleibt

- **Nicht in Studio geprüft:**
  - Nichts ist importiert. `studio_hubkit_templates.luau` ist nur syntaktisch geprüft (StyLua parst die Datei), nicht ausgeführt.
  - Die Achsen sind vom Plot Kit übernommen: Blender (x, y, z) wird Roblox (−x, z, y).
  - Ob die Seats richtig sitzen und die PointLight hell genug ist, zeigt erst ein Playtest.
- **Moos am Felsen** wirkt eher wie eine runde Kappe als wie überhängendes Moos. Der Nutzer hat den Felsen am 06.11.2026 so abgenommen.
- **Türme ragen durch Überhänge:** Kronen (Tropfen ab etwa 4), Laternenarm (2,75 vom Mast) und Schirm (Kante 7,4) haben keine Kollision. Ein Spielerturm geht hindurch, wie bei jeder Deko ohne Dach-Kollision. Die Modelle deshalb nicht direkt an Laufwege setzen.
- **Unter den Drehpunkt** reichen FlowerBush (0,16, Kugelrundung), ParkBench (0,11) und Rock (0,03). Das fällt nicht auf.
- **Tor:** Die Schrift ist Geometrie in der eingebauten Blender-Schrift (Inter, etwas fetter gemacht). Für einen anderen Text müssen Skript und Export neu laufen.
- **Vorschaubilder** kommen aus EEVEE. Das Laternenglas leuchtet nur schwach, das Glühen kommt erst in Studio mit Neon.
- `assets/HubKit/previews/` und `assets/HubKit/fbx/` stehen in `.gitignore`, wie beim Plot Kit. Beide erzeugt `run_hubkit.py`, die Vorschauen liegen zusätzlich im Vault unter „Hub Kit Vorschau“.
- **Pfeilschrift nicht in Studio gesehen:** Die SurfaceGui-Fläche ist aus der Pfeilform gerechnet. Die Richtung, Front = Blender −Y, ist dieselbe wie beim Plot Sign. Ob das Wort ganz auf dem Brett sitzt und nicht spiegelverkehrt ist, zeigt erst der Import.
- **IceTree ist mit 19 höher als die Referenz** (14 bis 16), weil der Stamm doppelt so lang sein sollte.

## Import in Studio (Klicks)

1. Studio mit dem Place öffnen, Edit-Modus (kein Playtest).
2. **Datei → 3D importieren** (File → Import 3D). Im Dateidialog nach `C:\Users\Wobble\Desktop\roblox\assets\HubKit\fbx` gehen und `HubKit_IceTree.fbx` wählen. Wenn der Dialog Mehrfachauswahl erlaubt, Strg halten und alle 13 `HubKit_*.fbx` anklicken, dann **Öffnen**. Sonst die Schritte 2 und 3 je Datei wiederholen.
3. Im Importfenster:
   - Die Meshes **nicht zusammenführen**: Jede Farbe und jedes Teil muss ein eigener MeshPart bleiben, sonst gehen Varianten, Licht und Pfeilflächen verloren.
   - „In Workspace einfügen“ angehakt lassen.
   - Die Einheit bleibt Studs, die Größe 1:1.
   - Dann **Importieren**. Jedes Modell landet als `HubKit_<Model>` im Workspace.
4. **Ansicht → Befehlsleiste** (View → Command Bar) öffnen. Den ganzen Inhalt von `assets/HubKit/studio_hubkit_templates.luau` hineinkopieren und **Enter** drücken. Das Skript macht Folgendes:
   - Es setzt Farben, Kollision, Seats, Neon und Licht der Laterne, das durchsichtige Wasser und die Schrift auf den Pfeilen.
   - Es legt alle Modelle als Vorlagen in `ServerStorage.HubKit`, dazu die Varianten `IceTree_Blue`, `IceTree_Choco`, `Barrel_Pink`, `Barrel_Blue`, `Crate_Pink` und `Crate_Blue`. Im Workspace sind sie danach verschwunden.
   - Die Ausgabe nennt je Modell die Zahl der Meshes, Kollisionsteile, Seats, Lichter, Schilder und Varianten.
5. Prüfen: `ServerStorage.HubKit` aufklappen und je eine Vorlage in den Workspace ziehen.
   - `Lantern`: Leuchtet das Glas, steckt eine PointLight im MeshPart `Lantern_Lamp`?
   - `IceTree_Choco`: Ist die Krone braun?
   - `Signpost`: Stehen „SHOP“, „UPGRADES“ und „ISLANDS“ lesbar und nicht gespiegelt auf den Pfeilen?
   - `Crate_Pink`: Sind die Seiten geschlossen?
   - `ParkBench`: Mit Play setzen, sitzt die Figur auf der Bank?
   - Danach die Kopien wieder löschen.
6. **Datei → Speichern** (Strg+S) bzw. veröffentlichen.

Platzieren kommt danach: Vorlagen kopieren und auf den Hub-Ring setzen, das Hafentor an den späteren Hafen.

## Im Place: Deko und Wege auf dem Hub-Ring

Seit 06.11.2026 vom Nutzer freigegeben, Skript `studio_hub_decor.luau` (Befehlsleiste, Edit-Modus). Es braucht die Vorlagen in `ServerStorage.HubKit`.

Alles liegt in `Workspace."Ice Cream Map".Dekoracje.Hub`. `Dekoracje` ist für Landepunkte gesperrt (`Config/Map.landing.blockedFolders`), deshalb stört der Ordner keine Regel. Mit einem Klick auf `Hub` lässt sich alles ausblenden oder entfernen. Vorher `RESTORE_PLOT_PATHS = true` laufen lassen, sonst schweben die angehobenen Wegsteine der Plots.

Inhalt von `Hub`:

- **`Sektor_01` bis `Sektor_12`:**
  - `Wege`: von der Rampe zur Brücke und vier Stücke des Ringwegs.
  - `PlotWege`: die Wege auf dem Plot.
  - Vorplatz am Brückenkopf: zwei Laternen links und rechts, die Arme zeigen zur Brücke. Dazu eine Bank und ein Mülleimer am Wegrand und ein Waffel-Blumentopf.
  - Außerhalb des Ringwegs, Richtung Sektor k + 1: eine Baumgruppe aus 2 oder 3 Eisbäumen, zwei Blumenbüschen und einem Felsen. Die Kronen sind in der Sortenfarbe des Sektors und des Nachbarn.
  - Innerhalb des Ringwegs auf der anderen Seite: drei Kisten, eine davon gestapelt, und zwei Fässer. Die Rahmen sind bunt gemischt, in den Sortenfarben und in Holz.
- **`Einzelstuecke`:**
  - Bei 180° der Brunnen mit zwei Bänken und dem Picknicktisch.
  - Bei 300° am Außenrand das Hafentor „Coming Soon“, davor der Wegweiser „SHOP / UPGRADES / ISLANDS“.
  - Je ein Stichweg vom Ringweg zu beiden.
- **`Platzhalter`:**
  - Je eine flache, halb durchsichtige Platte 44 × 30 (r 200 bis 230) mit Namen für `UpgradeShop` (0°), `CosmeticShop` (120°) und `QuestHub` (240°). Sie haben keine Kollision und keine Abfragen.
  - Je ein Stichweg vom Ringweg. Dort steht keine Deko.

**Wege:**

- **Aufbau:** Die Oberseite liegt 0,52 über dem Boden. Im Hub ist sie Ring-Pflaster `WS_Pavers` in #FFF4E4, auf den Plots Creme. Beidseitig läuft ein runder Bordstein in Karamell #C98A4F, 0,6 breit, dessen Rundung knapp unter der Oberseite endet. Wo sich zwei Wege kreuzen, verdeckt jede Oberseite den Bordstein des anderen, die Kreuzungen sind glatt.
- **Rampe bis Brücke:** Bis r 211 ist der Weg 12 breit, denn der Eingangsbogen lässt nur 12,9 zwischen seinen Füßen. Danach folgt der Vorplatz, 18 breit wie die Brücke, und endet auf ihr.
- **Ringweg:** 8 breit bei r 192, aus 48 geraden Stücken.
- **Wo keine Wege sind:** Die Wege beginnen erst an der Rampenoberkante, in der Arena und auf den Rampen bleibt alles eben.
- **Plots:** Einstieg von der Brücke, Weg zum Wagen, Querachse zu Station und Truhe, runder Platz. Die Wegsteine des Plot Kits sind dafür 0,42 angehoben (Attribut `WalkwayLift`).

**Regeln, die das Skript einhält und prüft:**

- **Weg frei:** Kein Modell ragt in den 20 Studs breiten Weg von der Rampenoberkante (r 159) zur Brücke (r 232). Geprüft wird der gedrehte Umriss, Baumkronen und Schirm eingeschlossen. Die Ausgabe nennt jede Verletzung.
- **Wiederholbar:** Ein erneuter Lauf baut die gewählten Sektoren und Stücke neu. Die Wegsteine werden dabei nur einmal angehoben.

**Stand am 06.11.2026:**

- **Umfang:** 137 Modelle, 1.807 Teile, alle verankert. Davon sind 649 Teile Wege. Dazu kommen 24 PointLights (eine je Laterne) und 31 Sitze.

  | Modell | Anzahl |
  |---|---|
  | Lantern | 24 |
  | Crate | 21 |
  | IceTree | 15 |
  | Barrel | 14 |
  | FlowerBush | 14 |
  | ParkBench | 14 |
  | TrashBin | 12 |
  | WafflePlanter | 12 |
  | Rock | 7 |
  | Fountain, PicnicTable, HarborGate, Signpost | je 1 |

- **Überschneidungen:** Keine Kollision eines Modells schneidet einen Weg, ein anderes Modell oder die Map.
- **Playtest:**
  - Gehen (20,9), Sprint (27,1) und Dash bleiben an jeder Kante ohne Tempoverlust: Rampe zum Weg, Bordstein quer, Ringweg, Vorplatz zur Brücke, Plot-Wege. Geprüft in Sektor 1 und von der Rampe bis zur Brücke in den Sektoren 3, 7, 10 und 12, dazu der Ringweg über die Shop-Lücke bei 0° und die Brunnen-Lücke bei 180°.
  - Der Teleport zu Arena und Plot funktioniert.
  - Der ServePoint ist über den Weg vor dem Wagen erreichbar, die Figur steht dort 1,2 vom Punkt entfernt (Grenze 12). Ein echtes Servieren mit gefangenen Kugeln habe ich nicht getestet.
- **Konsole beim Start:** 11.837 Landepunkte, wie vor dem vollen Ausbau. Die Landepunkte liegen nur im Umkreis 135 um die Big Swirl, der Hub kann sie nicht verändern. Keine neue Warnung. Die drei Meldungen `Covery.CoverBlock_10: its meshes stuck out of Collision` betreffen die Arena-Deckung, an der der Hub nichts ändert. Sie standen schon im ersten Playtest mit nur Sektor 1 da.
- **Screenshots:** im Vault unter „Hub Deko Vorschau“.

**Stand am 07.11.2026: Beete, Zaun, Füllgebäude, Licht**

- **Grasbeete:** am Abend durch die Wiese ersetzt (siehe unten).
- **Zaun (`Sektor_XX.Zaun`):**
  - Er besteht aus `FenceSection` und `FencePost` aus dem Plot Kit, gesetzt bei r 231.
  - Die Kappen sind Karamell #C98A4F, die Pfosten Schoko #6E4029.
  - An jeder Brücke ist eine Lücke von 22,4 (der Weg ist 20 breit), am Hafentor eine von 28.
  - Die Modelle haben keine eigene Kollision. Unsichtbare Wände bis y 40 stehen in `Sperre.Hubzaun.Sektor_XX` und stoppen nur Spieler (`playersOnlyFolders`). `studio_arena_rim.luau` lässt sie beim Neuaufbau der Sperre stehen.
- **Füllgebäude (`Einzelstuecke`, `BUILDINGS`):**
  - Café am Brunnen (Akzent Schoko), Pavillon im äußeren R-Beet von Sektor 2 (Akzent Mango), Kiosk am Innenfeld beim Hafentor (Akzent Lavendel).
  - Nur das MeshPart `<Model>_Pink` (Markise, Schild, Kissen) nimmt die Sortenfarbe an.
  - Die `CartGarage` liegt in `ServerStorage.HubKit`, steht aber nicht im Place.
- **Laternen:** Das PointLight ist an, mit Helligkeit 1 und Reichweite 14. In der Vorlage ist es aus.
- **Umfang:** 330 Modelle und 2.597 Teile im Hub, alle verankert. Davon sind 649 Wege, 126 Beete und 531 Zaun. Dazu kommen 177 Sperrwände in `Sperre.Hubzaun`.

  | Modell | Anzahl |
  |---|---|
  | FenceSection | 164 |
  | FlowerBush | 27 |
  | Lantern | 24 |
  | Crate | 21 |
  | IceTree | 15 |
  | Barrel, ParkBench | je 14 |
  | FencePost | 13 |
  | TrashBin, WafflePlanter | je 12 |
  | Rock | 7 |
  | Cafe, Pavilion, IceKiosk, Fountain, PicnicTable, HarborGate, Signpost | je 1 |

- **Playtest:**
  - In allen 12 Sektoren geht man von r 165 bis r 249 auf die Brücke, je 4,0 bis 4,2 s in Gehtempo.
  - Teleport zu Arena und Plot funktioniert.
  - Servieren mit 3 gesetzten Kugeln funktioniert (`StudioTowerTest`, dann zum ServePoint gelaufen).
  - Am Hafentor stoppt das geschlossene Tor selbst, wie vorgesehen. Die Zaunlücke ist frei.
  - Keine Kollision schneidet Wege, Plot-Wege oder Shop-Flächen.
  - Keine neue Warnung. Die Meldung `rbxassetid://203785492 … Asset type does not match` steht weder im Place noch im Repo, sie kommt vom Studio-Avatar.
- **Screenshots:** im Vault unter „Hub Deko Vorschau“, Dateien `2026-11-07 …` und `Komplett_*`.

**Stand am 07.11.2026 abends: Wiese, Terrain-Gras, Leaderboard-Platz**

- **Wiese (`Sektor_XX.Rasen`, `LAWN`):**
  - Pro Sektor und Seite gibt es ein Feld innen und eins außen vom Ringweg, also 48 Teile für den ganzen Hub, je eine `UnionOperation`. Sie reichen von der Wegmitte bis zur Lücke, dort läuft das Feld des Nachbarn nahtlos weiter.
  - Das Gras geht bis an jeden Bordstein und füllt die Zwickel zwischen Ringweg, Rampenweg und Zaun. Am Ringweg ist der Rasen aus Stücken von 7,5° gebaut, so liegt seine Kante genau auf den geraden Bordsteinen.
  - Ausgeschnitten und damit gepflastert bleiben:
    - der Weg Rampe–Brücke (bis 6,6 von der Mitte),
    - der Vorplatz an jeder Brücke (|u| < 19,5 ab r 207, runde Ecken),
    - die Shop-Flächen (±24, nur außen),
    - der Brunnen mit Café (außen −38 bis +18, innen ±8 um den Picknicktisch),
    - das Hafentor (außen ±15, innen ±8 um den Kiosk),
    - der Platz vor dem Pavillon in Sektor 2 (`PLAZAS`).
  - Der Rasen ist 0,08 hoch, vorher waren die Beete 0,26. Er hat keine Kollision und keine Abfragen. Lose Kugeln liegen deshalb auf dem Ring darunter. Bei 0,26 sanken sie sichtbar ein, bei 0,08 liegen sie wie auf dem Pflaster.
  - Die Farbe ist #82B84E, auf Rasen und Terrain-Gras gleich, damit es ohne Halme genauso aussieht. Die Schnitte sind CSG mit `SplitApart = false` und `PreciseConvexDecomposition`. Mit `Box` träfe die Terrain-Prüfung auch die ausgeschnittenen Wege.
- **Terrain-Gras (`GRASS_TERRAIN`, `Terrain.Decoration`):**
  - Unter dem Rasen liegt eine dünne Schicht Grass-Terrain. Die untere Voxel-Lage (y 4–8) ist zu 0,72 gefüllt, so liegt die Oberfläche bei höchstens y 8,88, unter dem Pflaster.
  - Die Halme wachsen durch Ring und Rasen nach oben, das Terrain selbst sieht man nirgends.
  - Gras bekommt nur eine 4er-Säule, deren Mitte und acht Punkte im Abstand 3,5 rundherum auf Rasen liegen: 1.530 Säulen. Unter keinem Weg oder Bordstein liegt Gras, das prüft das Skript nach jedem Lauf.
  - Messwert: Eine volle untere Lage ergibt die Oberfläche y 10, jede Füllung der oberen Lage hebt sie weiter (+4 je 1,0).
- **Eis-Bäume:** höchstens 2 je Sektor statt 3, aufrecht.
- **Leaderboard-Platz (`LEADERBOARD`):**
  - Der Platzhalter `Platzhalter_Leaderboard` steht vor dem Cosmetic Shop, innen am Ringweg (r 180), 17 neben der Shop-Achse und um 25° zu den Brücken gedreht.
  - Er ist ein pinkes Brett 10 × 11 ohne Kollision.
  - In der Sichtprüfung vom Weg Brücke–Rampe (Sichtlinie frei, höchstens 50° neben der Laufrichtung, Vorderseite sichtbar) sahen ihn 23 von 48 Wegpunkten, aus den Sektoren 11, 12 und 1. Direkt vor der Shopfläche wären es 16.
- **Umfang:** 329 Modelle und 2.511 Teile im Hub, die ganze Map hat 7.787 Teile. Sicherung des Hubs vor der Wiese: `ServerStorage."MapBackup_2026-11-07_HubVorWiese"`.
- **Geprüft am 07.11.2026:**
  - Kein Modell steht im 20er-Weg, keine Kollision liegt auf einem Weg, kein Terrain-Gras unter Wegen.
  - Lose Kugeln auf dem Rasen in Sektor 1 und 7 liegen wie auf dem Pflaster (Unterkante 9,00 bzw. 8,75 je nach Größe).
  - Teleport zu Arena (r 162) und Plot (r 318) funktioniert. Servieren am Plot funktioniert.
  - Keine neue Warnung.
- **Variante B** (Grasbüschel aus Blender) wurde getestet und verworfen.

**Nach einem neuen Lauf von `assets/PlotKit/studio_plotkit_place.luau`** liegen die Wegsteine wieder tief. Dann `studio_hub_decor.luau` noch einmal laufen lassen.
