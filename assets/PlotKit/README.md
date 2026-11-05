# Plot Kit

Die Modelle für die Plot-Inseln im Eiscreme-Stil der Referenzbilder, gebaut am 05.11.2026 aus den Bausteinen und Farben des Arena-Kits (`assets/ArenaKit/arenakit.py`): glänzender Cartoon-Stil, runde Kanten, Farbe als Variante, keine Texturen. Der Stil ist freigegeben.

Am selben Tag folgte eine Korrekturrunde:
- Sell Cart, Working Station und Scoop Chest sind 1,5-mal so groß, das Plot Sign 1,3-mal. Die Theken von Wagen und Station liegen trotzdem auf 3,5.
- Der Zaun ist neu: dickere Creme-Latten, Pfosten in warmem Holz mit Pink-Kappe, derselbe Pfosten in FencePost und FenceSection.
- Das Gras ist pastelliger.

Noch nicht in Studio importiert.

- Blender-Datei: `assets/PlotKit/PlotKit.blend` (je Modell eine Collection `PK_<Model>`, dazu `PK_Layout` und `PK_Preview` nur für die Bilder)
- Skripte: `plotkit.py` (Kit, R15-Figur, Vorschau, Export), `build_plot_pack.py` (die Modelle, die Skalierung `SCALE`, das Gesamtbild), `run_plotkit.py` (alles im Hintergrund-Blender), `studio_plotkit_templates.luau` (macht in Studio Vorlagen aus dem Import)
- FBX: `C:\Users\Wobble\Desktop\roblox-assets\PlotKit\PlotKit_<Model>.fbx`
- Vorschauen: `assets/PlotKit/previews/<Model>.png` (nicht im Repo, `.gitignore`; `run_plotkit.py` erzeugt sie neu) und im Vault `Wobble Scoops\Plot Kit Vorschau\`. Jedes Bild zeigt von links nach rechts vorne, schräg und oben, mit einer R15-Figur (5,2 Studs) samt Waffel-Rucksack und Turm aus 20 Kugeln (voller Starter-Becher, 30 Studs).
- Maße und Daten maschinenlesbar: `assets/PlotKit/plotkit_models.json`

Neu bauen (Blender muss nicht offen sein):
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/PlotKit/run_plotkit.py -- SellCart +layout
```
Ohne Namen baut es alle Modelle. `+layout` rendert das Gesamtbild und die Ansicht von der Brücke.

## Modelle

Maße in Studs, so wie sie in Roblox stehen: Breite (X) × Tiefe (Z) × Höhe (Y). Der Drehpunkt liegt bei allen unten mittig, die Vorderseite (wo der Spieler steht) ist −Z, also die Front in Roblox. Die Dreiecke sind die exportierten, mit angewandten Modifiern. Die Skalierung ändert sie nicht.

| Modell | Maße | Dreiecke | Kollision (Roblox, ab Drehpunkt) | FBX | Vorschau |
|---|---|---|---|---|---|
| SellCart (×1,5) | 19,5 × 10,5 × 21,2 | 9.880 | Box 17,4 × 3,53 × 9,3 (bis Thekenoberkante), Mitte (0; 1,76; 0) | `PlotKit_SellCart.fbx` | `previews/SellCart.png` |
| WorkingStation (×1,5) | 36,0 × 12,0 × 25,4 | 15.816 | 4 Boxen: Theke 16,8 × 3,53 × 2,85 bei (0; 1,76; −3,0), Rückwand 17,7 × 14,1 × 1,2 bei (0; 7,05; 4,8), Seiten mit Tank und Kiste je 9,45 × 13,95 × 10,2 bei (±12,68; 6,98; 0,3) | `PlotKit_WorkingStation.fbx` | `previews/WorkingStation.png` |
| ScoopChest (×1,5) | 14,0 × 8,9 × 13,7 | 4.938 | Box 13,95 × 9,9 × 7,95, Mitte (0; 4,95; 0) | `PlotKit_ScoopChest.fbx` | `previews/ScoopChest.png` |
| PlotSign (×1,3) | 14,0 × 2,7 × 12,2 | 3.972 | Box 11,2 × 9,0 × 1,56, Mitte (0; 4,49; 0) | `PlotKit_PlotSign.fbx` | `previews/PlotSign.png` |
| PathStraight | 6,0 × 4,0 × 0,32 | 352 | keine | `PlotKit_PathStraight.fbx` | `previews/PathStraight.png` |
| PathCurve | 10,0 × 10,0 × 0,32 | 884 | keine | `PlotKit_PathCurve.fbx` | `previews/PathCurve.png` |
| PathRound | 14,0 × 14,0 × 0,55 | 2.376 | keine | `PlotKit_PathRound.fbx` | `previews/PathRound.png` |
| FencePost | 2,2 × 2,2 × 4,9 | 932 | Box 1,65 × 4,05 × 1,65, Mitte (0; 2,03; 0) | `PlotKit_FencePost.fbx` | `previews/FencePost.png` |
| FenceSection | 9,1 × 2,2 × 4,9 (Pfosten bei x −4, Latten bis +4) | 1.324 | Pfosten-Box wie FencePost bei (−4; 2,03; 0), Latten-Box 7,55 × 3,38 × 0,6 bis zum Boden bei (0,23; 1,69; 0) | `PlotKit_FenceSection.fbx` | `previews/FenceSection.png` |

Gesamtbild:
- `previews/PlotLayout.png` zeigt alles auf einer 110 × 60-Insel (begehbar 104 × 54), schräg und von oben.
- `previews/PlotLayout_Bridge.png` zeigt die Ansicht aus Spielerhöhe (Augen bei 4,6) von der Brücke, 26 Studs vor der Insel.

### Davorstehen mit vollem Turm

Der Turm steht 1,5 Studs hinter dem Spieler. Gerechnet ist ein Spieler direkt an der Kollision, mit dem Turm auf der Seite zum Modell:
- Sell Cart: 1,1 Studs zwischen Turm und Vordachkante.
- Working Station: 0,7 Studs zwischen Turm und Vordachkante.
- Scoop Chest: Über dem Standplatz hängt nichts.

Über den Platz vor den Modellen ragt also nichts in den Turm.

### Details je Modell

- **SellCart** (Referenz „3D-Eiswagen-Modellübersicht in Pink unerquicklich“): rosa Wagen mit gestreiftem Giebel-Vordach und goldener Firstleiste. Oben sitzt das Kegel-Abzeichen in einem Goldring, an den vorderen Pfosten hängen zwei Laternen. Auf der Theke stehen Kasse mit Bildschirm, ein Waffelstapel und eine Ablage mit 6 Kugeln. Je ein Speichenrad vorne und hinten, kleine Stützräder, Creme-Glasur mit Tropfen über der Theke. Die **Theke liegt auf 3,5**, obwohl der Wagen 1,5-mal so groß ist: Wagenkasten und Räder sind niedriger gebaut, Vordach, Abzeichen und Laternen bleiben hoch. Ein Spieler davor ragt ab der Hüfte darüber.
- **WorkingStation** (Referenz „Naschwerkstatt für Eiscreme-Handwerk“): Bude mit gestreiftem Giebel-Vordach und Zahnrad-Abzeichen mit Kegel, Rückwand, Theke mit Werkzeug-Emblem, Bildschirm und zwei Flaschen. Hinten links eine Rührschüssel unter einer goldenen Düse. Links und rechts je ein Creme-Tank mit Pink-Glasur, Anzeige und dickem Goldrohr zum Dach, davor Holzkisten (links Emblem, rechts Gold-X). **NPC-Platz:** freier Boden 15 × 6 zwischen Theke und Rückwand, Mitte bei (1,2; 0,45; 1,5) in Roblox, Bodenhöhe 0,45. Ein rosa Teppich markiert ihn, der NPC ist nicht gebaut. Die Kollision schließt den Bereich ringsum ab. Die **Theke liegt auf 3,5**: Eine R15-Figur am NPC-Platz schaut mit dem Oberkörper darüber. Die Vorschau zeigt dafür einen NPC-Platzhalter ohne Turm.
- **ScoopChest** (Referenz „Glänzende Eistruhe mit bunten Eiskugeln“): rosa Unterbau mit Waffelgitter vorne, Creme-Glasur mit Tropfen, Kegel-Emblem und blauen Lüftungsschlitzen an den Seiten. Drin stehen auf zwei Stufen 8 Kugeln in Goldschalen, hinten ein fester Rahmen mit Abzeichen. **Der Deckel ist ein eigenes Teil:** die gewölbte Glashaube mit rosa Seitenrahmen, Vorderkante, Griff und Scharnier, exportiert als `ScoopChest_Lid_Glass`, `_Lid_Pink` und `_Lid_Gold`. Die Scharnierachse läuft entlang X bei y 9,0, z 2,55 (Roblox, ab Drehpunkt). Zum Öffnen dreht sich der Deckel dort um X, die Vorderkante geht hoch, etwa 100°. Das Glas wird in Studio SkyBlue mit 0,55 Transparenz.
- **PlotSign** (Referenz „Bunte Eiscreme-Spielwelt_ Plot-Schild Varianten“): zwei Waffelpfosten mit Creme-Kappe, Pink-Tropfen und Seilringen, ein Brett mit Pink-Glasur, Kegel-Abzeichen oben und Laternen außen. **Freie Fläche:** `PlotSign_Face_Cream`, 7,3 × 3,25 Studs, Mitte (0; 5,79; −0,52), in einem erhabenen Waffelrahmen mit Goldnieten. Name und Level kommen später per SurfaceGui auf ihre Front (Face = Front).
- **PathStraight, PathCurve, PathRound** (Referenz „Bonbon-Wege für Eiscremewelten“): abgerundete altrosa Steine auf einem Creme-Bett, 0,32 hoch, Wege 6 breit.
  - PathStraight ist 4 lang und lässt sich aneinanderreihen.
  - PathCurve ist eine Viertelkurve (innen r 4, außen r 10). Ihr Bogenmittelpunkt liegt bei (−5; ·; −5) in Roblox ab Drehpunkt. Beide Enden sind 6 breit.
  - PathRound ist die Rundplatte (Ø 14) mit liegendem Kegel-Emblem in der Mitte.
  - Ohne Kollision (begehbare Deko): Den Drehpunkt 0,2 unter die Grasfläche setzen, dann stehen die Füße nicht in der Luft.
- **FencePost, FenceSection** (Referenz „Stilisierter Holzzaun mit rosa Akzenten“): **ein** Pfosten für beide Teile. Er ist kantig und aus warmem Holz (Waffle), steht auf einem Creme-Fuß mit Pink-Ring und trägt eine Pink-Glasurkappe mit Tropfen und eine Creme-Kugel, 4,9 hoch. FencePost ist dieser Pfosten allein. FenceSection ist derselbe Pfosten am linken Ende (x −4) plus zwei dicke Creme-Latten (0,6 × 0,75) und vier Sprossen bis x +4.
  - Aneinandergereiht (Drehpunkte 8 Studs auseinander, gleiche Drehung) steht alle 8 Studs ein Pfosten.
  - Ans offene Ende einer Reihe kommt ein FencePost.
  - Im Gesamtbild läuft der Zaun einmal herum. Jedes Stück hat seinen Pfosten am Anfang in Laufrichtung, so steht an jeder Ecke genau ein Pfosten.

### Gesamtbild (`previews/PlotLayout.png`, `previews/PlotLayout_Bridge.png`)

Im Rahmen des Plots (`Config/Map.plot`, `PlotLayout`: x = u entlang des Rings, rechts von der Brücke aus gesehen; y = v entlang der Spur; die Brücke trifft die Vorderkante bei v −30 mittig):
- Der **Sell Cart** steht mittig am Brückenkopf bei (0, −17) und schaut zur Brücke. Ein Spieler an seiner Theke steht am ServePoint (0, −24).
- Davor liegt ein Vorplatz (x −16 bis 16). Links und rechts führt je ein Weg bei x ±13 am Wagen vorbei zur **Rundplatte** (0, −1).
- Von der Platte gehen Wege nach hinten zur **Working Station** (0, 16,5), nach rechts zur **Scoop Chest** (28, −1, zur Platte gedreht) und nach links mit PathCurve Richtung hinten.
- Das **Schild** steht bei (24, −26) und schaut zur Brücke.
- Ein **Zaun** läuft bei ±48 / ±24 rundherum, mit 16 Studs Lücke für die Brücke.
- Links und hinten bleibt Platz frei. Es gibt keinen Upgrade-Bereich, der kommt auf die Hauptinsel.

## Grasboden in Studio

Behalten (Freigabe 05.11.2026):
- die MaterialVariant `WS_Grass` auf den 12 `Powierzchnia`, seit der Korrekturrunde mit dem pastelligeren Bild rbxassetid://79201403556010 (vorher rbxassetid://111206069018985)
- die Zonen-Marker (`Strefy`) auf 0,8 Transparenz
- die 72 Inselkörper `Wyspa_*` oben 0,1 tiefer, gegen Flackern

Skript und Bild:
- Skript: `assets/ArenaKit/studio_plot_grass.luau`
- Bild: `assets/ArenaKit/textures/Plot_Grass.png`, erzeugt von `assets/ArenaKit/make_floor_textures.py` (`GRASS`, mit `ONLY = {"Plot_Grass"}` nur dieses Bild)

Der Place muss noch gespeichert werden.

## Was nicht gelungen ist oder offen bleibt

- **Kein Licht in den Laternen:** Das Glas ist Gold und mit dem übrigen Gold zu einem Mesh verschmolzen. Leuchten (PointLight und Neon-Glas) braucht ein eigenes Teil oder Attachments an den Laternen. Die Positionen stehen in `build_plot_pack.py` (`lantern(...)`).
- **Weggelassene Deko aus den Referenzen:** Büsche, Blumen, Steine, Flaschen auf dem Wagen, die Eckpfeiler mit Eis-Laternen am Zaun, der leuchtende Verkaufskreis, Sterne und Lichter in der Truhe, Kasse und Kessel-Details der Werkstatt.
- **Working Station:** Mit 15.816 Dreiecken ist sie das größte Modell. Sparpotenzial gibt es bei den Rohren und Zahnradzähnen.
- **Zaunpfosten:** In der Draufsicht hat die Pink-Kappe eine schmale Naht an ihrem Saum (Glasur-Vorhang). Nicht behoben.
- **Unter den Drehpunkt** reichen Sell Cart und Working Station bis 0,12 (Radrundung, Fasen). Das fällt nicht auf.
- **Zwei Farben über die Kit-Palette hinaus:** `Stone` #E2A4B4 für die Wegsteine und `Glass` (SkyBlue, durchsichtig) für die Truhenhaube.
- **Schild-Position:** Laut `Config/Map.plot` steht das Schild bei u 13, dort läge es auf dem Vorplatz. Im Gesamtbild steht es bei u 24. Die Config ist nicht geändert (keine Code-Änderungen).
- **Ungeprüft in Studio:** `studio_plotkit_templates.luau` ist nur syntaktisch geprüft, nicht ausgeführt. Die Achsen (Blender −Y wird Roblox −Z, Blender Z wird Roblox Y, der Drehpunkt bleibt am FBX-Ursprung) habe ich an der vorhandenen Vorlage `ServerStorage.ArenaKit.WaffleCrate` nachgemessen, nur lesend.
- **Vorschaubilder** sind aus EEVEE, ohne Glühen. Die Figur ist ein klobiger R15-Platzhalter, ihr Turm hat 20 Kugeln. Den größten Turm (65 Kugeln, rund 100 Studs) prüfen die Abstände oben.

## Import in Studio (Klicks)

1. Studio mit dem Place öffnen, Edit-Modus (kein Playtest).
2. **Datei → 3D importieren** (File → Import 3D). Im Dateidialog nach `C:\Users\Wobble\Desktop\roblox-assets\PlotKit` gehen und `PlotKit_SellCart.fbx` wählen. Wenn der Dialog Mehrfachauswahl erlaubt, Strg halten und alle neun `PlotKit_*.fbx` anklicken, dann **Öffnen**. Sonst Schritt 2 bis 3 je Datei wiederholen. Ob die Mehrfachauswahl geht, habe ich nicht geprüft.
3. Im Importfenster:
   - Die Meshes **nicht zusammenführen**, jede Farbe muss ein eigener MeshPart bleiben (wie beim Arena-Kit).
   - „In Workspace einfügen“ angehakt lassen.
   - Die Einheit bleibt Studs, die Größe 1:1.
   - Dann **Importieren**. Jedes Modell landet als `PlotKit_<Model>` im Workspace.
4. **Ansicht → Befehlsleiste** (View → Command Bar) öffnen. Den ganzen Inhalt von `assets/PlotKit/studio_plotkit_templates.luau` hineinkopieren und **Enter** drücken. Das Skript setzt Farben, Kollision, Deckel mit Scharnier und Schildfläche. Danach liegen alle Modelle als Vorlagen in `ServerStorage.PlotKit` und sind aus dem Workspace verschwunden. Die Ausgabe nennt je Modell die Zahl der gefärbten Meshes und der Kollisionsteile.
5. Prüfen: `ServerStorage.PlotKit` aufklappen, eine Vorlage (z. B. `ScoopChest`) in den Workspace ziehen und ansehen.
   - Glas halbdurchsichtig?
   - `Lid` mit `Hinge` vorhanden?
   - Danach die Kopie wieder löschen.
6. **Datei → Speichern** (Strg+S) bzw. veröffentlichen.

Platzieren kommt danach: Vorlagen kopieren und auf die Inseln setzen, nach dem Gesamtbild.
