# Arena Kit 2

Arena-Überarbeitung Runde 1 (14.11.2026): neue Deckungen, Plattformen, Wahrzeichen und Spezial-Deckungen, damit die Arena nicht mehr aus Kopien derselben Formen besteht. Referenz: Vault `Wooble scoops Map assets 1\Arena_Referenz_Komplett.png`. Gebaut wie Deco Kit und Hub Kit, mit denselben Bausteinen, Farben und derselben Pipeline: glänzender Cartoon-Stil, runde Kanten, Farbe als Variante, keine Texturen. `run_arenakit2.py` liest `hubkit.py` und die Bausteine sowie den Export-Teil von `build_hub_pack.py` mit umbenannten Namen (`HK_` → `AK2_`, `HubKit` → `ArenaKit2`) und ergänzt Kollisions-Keile für Rampen (`kind = "wedge"`, im Vorlagenskript unsichtbare WedgeParts).

- Blender-Datei: `assets/ArenaKit2/ArenaKit2.blend`, je Modell eine Collection `AK2_<Model>`
- Skripte: `build_arena_pack2.py` (die Modelle), `run_arenakit2.py` (alles im Hintergrund-Blender), `studio_arenakit2_templates.luau` (Vorlagen in Studio, erzeugt: Änderungen gehören in `build_arena_pack2.py`)
- FBX: `assets/ArenaKit2/fbx/ArenaKit2_<Model>.fbx` (nicht im Repo)
- Vorschauen: nur im Vault unter `Wobble Scoops\Arena Kit 2 Vorschau`
- Maße und Daten: `arenakit2_models.json`
- Flackern geprüft mit `assets/find_zfighting.py -- AK2_`: alle 22 Modelle sauber

Neu bauen:
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/ArenaKit2/run_arenakit2.py -- WaffleCrates ChocoWall
```

## Regeln

- Pivot unten mittig, Vorderseite −Z in Roblox, Maße in Studs gegen eine R15-Figur (5,2).
- Kollision aus Boxen, aufrechten Zylindern und Rampen-Keilen, so nah am sichtbaren Modell wie möglich und nie größer (keine unsichtbaren Wände). Runde Formen (Tüte, Lollipop-Scheibe, Bogen-Schultern) sind mit Stufen-Boxen innerhalb der Rundung angenähert. Dünne Deko (Streusel, Kirsche, Hebel, Waffelröllchen, Sahnepfütze) hat keine Kollision.
- Flächen zum Draufstehen sind flach: die Glasur-Platten der mittleren Deckungen (Oberkante 5,9) und der Plattformen (6,0). Streusel liegen darauf nur als Optik.
- Mittlere Deckungen 5,1 bis 6,4 hoch (bespringbar, Messung vom 14.11.2026: Sprung mit Hochsteigen an der Kante bis 6,8), hohe ab 10,85 (vom Boden nie erreichbar).

## Modelle

Maße Breite × Tiefe × Höhe in Studs (Höhe mit Streuseln und Kirsche; die begehbare Oberkante steht dabei), Dreiecke nach dem Export, Kollision = Anzahl der Formen, Varianten = umgefärbte Kopien.

| Gruppe | Modell | Maße | Dreiecke | Kollision | Varianten |
|---|---|---|---|---|---|
| mittel | WaffleCrates | 8,8 × 6,4 × 6,3 (Oberkante 5,9) | 2.388 | 3 Boxen | |
| mittel | FallenCone | 14,6 × 6,8 × 6,0 | 2.352 | 4 Stufen-Boxen, 1 Zylinder | Kugel Mint, Lemon |
| mittel | CookieStack | 7,1 × 7,0 × 6,0 (Oberkante 5,9) | 2.768 | 4 Zylinder | |
| mittel | ChocoBar | 9,3 × 5,3 × 6,1 (Oberkante 5,9) | 2.200 | 2 Boxen | |
| mittel | CandyBox | 6,9 × 7,5 × 6,1 (Oberkante 5,9) | 1.668 | 2 Boxen | Streifen Mint, Blue |
| hoch | SundaeCup | 9,7 × 9,7 × 14,1 | 5.140 | 5 Zylinder | |
| hoch | ChocoWall | 12,3 × 4,1 × 12,0 | 3.132 | 2 Boxen | |
| hoch | WaffleArch | 14,4 × 4,1 × 12,5, Durchgang 5,8 breit, 8,1 hoch | 3.684 | 10 Boxen | |
| hoch | GiantCupcake | 8,9 × 9,2 × 15,2 | 1.560 | 4 Zylinder | Frosting Pink, Mint |
| hoch | MacaronStack | 7,4 × 7,0 × 11,0 | 2.292 | 3 Zylinder | Mitte Lavender, Mint |
| hoch | CookieTower | 7,8 × 7,8 × 11,8 | 5.000 | 10 Zylinder | |
| Plattform | WafflePlatform | 16,4 × 28,1 × 6,6 (Oberkante 6,0), Rampe 7 breit, 16 lang (21°) | 3.108 | 3 Boxen, 1 Keil | |
| Plattform | CakePlatform | 16,8 × 21,2 × 6,0, Treppe 6 breit, 8 Stufen à 0,75 | 5.528 | 2 Zylinder, 8 Stufen-Boxen | |
| Wahrzeichen | GrandSundae | 20,4 × 20,4 × 31,7 | 5.224 | 5 Zylinder | |
| Wahrzeichen | CreamMountain | 25,7 × 25,7 × 23,7 | 5.324 | 5 Zylinder | |
| Wahrzeichen | LollipopTree | 13,0 × 11,0 × 25,6 | 4.680 | 2 Zylinder, 7 Boxen (Scheibe) | Spirale Blue, Mint |
| Spezial | WobbleTower | 5,4 × 5,5 × 11,8 | 2.688 | 6 Boxen | |
| Spezial | WobbleTowerFallen | 15,2 × 14,5 × 4,8 | 3.084 | 6 Boxen | |
| Spezial | CreamDispenser | 5,4 × 5,4 × 7,3 | 1.744 | 2 Zylinder | Streifen Mint, Blue |
| Spezial | CreamDispenserSpill | 7,8 × 11,2 × 7,3 (Pfütze ohne Kollision, Mitte 0,4/−5,2, r 3,6) | 1.882 | 2 Zylinder | Streifen Mint, Blue |
| Spezial | GummyPad | 7,8 × 7,8 × 6,3 | 1.724 | 4 Zylinder | Bär Mint, Lemon |
| Spezial | GummyPadPressed | 7,8 × 7,8 × 3,5 | 1.724 | 4 Zylinder | Bär Mint, Lemon |
| Spezial | GummyBouncer (16.11.2026) | 5,8 × 5,8 × 1,5 | 908 | 2 Zylinder | Bär Mint, Lemon |
| Spezial | GummyBouncerPressed | 5,8 × 5,8 × 1,1 | 908 | 2 Zylinder | Bär Mint, Lemon |
| hoch | WaffleWall (16.11.2026, der Waffelbogen ohne Durchgang) | 14,4 × 4,1 × 12,5 | 2.460 | 2 Boxen | |

Abweichungen vom Referenzbild: Die Kekse liegen gestapelt (hochkant hätten sie keine flache Oberseite). Der Keksturm ist eine hohe Deckung ohne Spiralweg: ein Weg, der für einen Spieler mit Turm breit genug ist (mindestens 6), bräuchte rund 26 Studs Durchmesser. Der Gummibär bleibt im eingedrückten Zustand auf dem Pad (gestaucht), nur der Spieler fliegt später. Der Sahne-Spender ist mit 7,3 Höhe weder „mittel“ noch „hoch“; oben ist er rund und nicht begehbar, das ist bei einer Spezial-Deckung gewollt.

Die beiden Zustände der Spezial-Deckungen sind je ein eigenes Modell mit demselben Pivot (`pair`/`state` in `arenakit2_models.json`), damit die spätere Spiellogik sie an derselben Stelle tauschen kann.

## Für die Anordnungs-Runde

`MapService.prepareCover` erwartet heute je Deckung in `Covery` genau eine Box `Collision` und vergrößert sie, wenn Meshes herausragen. Die Arena-Kit-2-Modelle haben mehrere Formen (`Collision` plus `Collision_<Name>`, Zylinder, Keile). So in `Covery` gestellt, würde die eine Box über das ganze Modell wachsen, also eine unsichtbare Wand werden. Vor dem Aufstellen muss `prepareCover` mehrere Kollisionsteile kennen und dann nichts vergrößern.

## Import in Studio (Klicks)

1. Studio mit dem Place öffnen, Edit-Modus (kein Playtest).
2. **Datei → 3D importieren** (File → Import 3D), im Dateidialog nach `C:\Users\Wobble\Desktop\roblox\assets\ArenaKit2\fbx` gehen und die 22 Dateien `ArenaKit2_*.fbx` wählen (geht die Mehrfachauswahl nicht, je Datei wiederholen).
3. Im Importfenster: Meshes **nicht zusammenführen** (jede Farbe bleibt ein eigener MeshPart), „In Workspace einfügen“ angehakt, Einheit Studs, Größe 1:1, **Importieren**. Jedes Modell landet als `ArenaKit2_<Model>` im Workspace.
4. **Ansicht → Befehlsleiste** (View → Command Bar), den ganzen Inhalt von `assets/ArenaKit2/studio_arenakit2_templates.luau` hineinkopieren, **Enter**. Das Skript setzt Farben, legt die unsichtbaren Kollisionsteile an (Boxen, Zylinder, Keile) und schiebt alles nach `ServerStorage.ArenaKit2` (mit den Farb-Varianten als `<Model>_<Variante>`).
5. Prüfen: eine Vorlage aus `ServerStorage.ArenaKit2` in den Workspace ziehen, ansehen, wieder löschen.
6. **Datei → Speichern** (Strg+S).

Noch nicht importiert, noch nicht in der Arena. Anordnung und Spiellogik der Spezial-Deckungen sind eigene Runden.
