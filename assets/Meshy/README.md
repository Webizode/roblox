# Meshy-Modelle

Fünf Modelle aus Meshy (27.11.2026), spielfertig gemacht und an die Stelle der alten Plot- und Shop-Kit-Modelle gesetzt. Die Originale liegen auf dem Desktop unter `meshy modelle`, Kopien mit sauberen Namen unter `assets/Meshy/source/` (60 bis 80 MB pro GLB, 1,8 bis 2,4 Millionen Dreiecke, nicht im Repo).

| Datei | Meshy-Name | ersetzt | wo im Spiel |
|---|---|---|---|
| `ScoopChest` | Enchanted_Ice_Cream_Chest | Scoop Chest (Plot Kit) | jeder Plot, `Ice Cream Map.Plots.Plot_NN.PlotKit.ScoopChest` |
| `SellCart` | Sprinkle_Sundae_Cart | Sell Cart (Plot Kit) | jeder Plot, `…PlotKit.SellCart` |
| `CraftingStation` | Sweet_Spell_Workshop | Working Station (Plot Kit) | jeder Plot, `…PlotKit.CraftingStation` (Funktion kommt später) |
| `UpgradeShop` | Sweet_Upgrade_Shop | Upgrade Shop (Shop Kit) | Hub, `Ice Cream Map.Dekoracje.Hub.Shops.UpgradeShop` |
| `CosmeticShop` | Sugar_Scoop_Boutique | Cosmetic Shop (Shop Kit) | Hub, `…Hub.Shops.CosmeticShop` |

## Ablauf

1. **Bauen** (Blender im Hintergrund, etwa 2 Minuten pro Modell):
   ```
   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/Meshy/build.py -- [ScoopChest ...]
   ```
   - reduziert auf das Dreiecks-Budget (`MODELS` in `build.py`),
   - behält die UVs des Originals (`MESHY_UV=smart` würde neue machen, das zerfällt in winzige Inseln),
   - backt Farbe, Normal, Rauheit und Metall vom Original,
   - setzt den Drehpunkt unten mittig mit der Front nach −Y,
   - skaliert gleichmäßig, damit das Modell in die Grundfläche des alten passt.

   Bei der Truhe trennt das Skript den Deckel ab und klappt ihn um 53° zu (`CHEST` in `build.py`). Außerdem misst es die 6 Becher aus.

   Ergebnis in `export/`: `<Name>.glb`, die Maps als PNG, `<Name>.json` (Maße, Dreiecke, Kollisionsbox, Scharnier, Becher) und `<Name>.blend`.
2. **Maps hochladen:** über das Studio-MCP (`upload_image`, `lune run scripts/serve-images assets/Meshy/export 8766`), die IDs in `maps.json` und in `studio_meshy_templates.luau` eintragen. Leere Metall-Maps (Shops) weglassen. Danach den Ladestatus prüfen.
3. **Importieren:** in Studio über *Datei → 3D importieren* die GLB aus `export/` mit Standard-Einstellungen. Jede kommt als Model „Scene“ in den Workspace. Der Importer dreht sie um 180°, das ist genau richtig: Danach liegt die Front bei −Z. Umrechnung Blender → Roblox: x → −x, z → y, y → z.
4. **Vorlagen:** `studio_meshy_templates.luau` ausführen (Edit). Es baut `ServerStorage.MeshyKit.<Name>` mit:
   - SurfaceAppearance (alle Maps);
   - unsichtbarer Box `Collision` (PrimaryPart, Drehpunkt unten mittig);
   - bei der Truhe `Lid` mit `Hinge` und den Attachments `ScoopSlot1` bis `ScoopSlot6`;
   - den Schildern SELL und COSMETICS.
5. **Aufstellen:** `studio_meshy_place.luau` ausführen.
   - Beim ersten Lauf kommen die alten Modelle nach `ServerStorage.MeshyBefore_2026-11-27` (mit Attribut `From`). Mit `BACK = true` stehen sie wieder da.
   - Bei weiteren Läufen werden die Meshy-Modelle an Ort und Stelle getauscht.

## v2: Meshys eigenes Remesh (seit 27.11.2026, alle fünf Modelle und der Quest Hub)

v1 (`build.py`) hat stark reduziert und Farbe, Normal, Rauheit und Metall neu gebacken. Das sah im Spiel schlecht aus: zerknitterte Formen, verschmierte Texturen, krakelige Schrift, grauer Metallglanz. v2 nimmt stattdessen Meshys eigenes Remesh:

1. **In der Meshy-Web-App:** Remesh auf 30.000 Dreiecke mit Dreieckstopologie, die GLB nach `Desktop/meshy modelle` laden. Der Pfad steht in `REMESH` in `build_v2.py`.
2. **Bauen:** `blender -b --factory-startup --python assets/Meshy/build_v2.py -- ScoopChest`
   - Nichts wird reduziert oder gebacken. Farb- und Normal-Map (2048) sind Meshys Dateien, Byte für Byte.
   - Metalness ist 0, die Rauheit eine flache Map mit 0,8.
   - Deckelschnitt, Zuklappen, Drehpunkt und Maßstab wie in `build.py`.
   - Jedes Teil bleibt unter 20.000 Dreiecken: Ein zu großes Teil wird in X-Scheiben geteilt.
   - Die Truhe hat drei Teile: `ScoopChest_Body` (10.227), `ScoopChest_Body2` (10.232) und `ScoopChest_Lid` (10.015).
   - Die anderen vier haben je zwei Teile mit etwa 15.000 Dreiecken.
   - Dazu kommt der Quest Hub: `Sundae_Scrolls_Kiosk` in Meshy, nur als Remesh vorhanden, ohne Quelle für `build.py`. Er ersetzt den Quest Hub aus dem Shop Kit. Der alte liegt in `ServerStorage.MeshyBefore_2026-11-27`. Aufgemalt ist nur die Schriftrolle mit Ausrufezeichen. Deshalb steht QUESTS auf der senkrechten Vorderkante der Markise (`SIGNS` in `studio_meshy_templates.luau`); die Oberseite der Markise ist von unten nicht zu sehen.
   - Ergebnis: `export/<Name>_v2.glb` und `_v2.json`.
3. **Import und Vorlage wie oben.**
   - Der Importer nennt die Teile jetzt `<Teil>_Node`, die Vorlage kommt mit beiden Namensformen zurecht.
   - Die importierten Farb- und Normal-IDs gelten für alle Teile. Nur die Rauheits-Map wird einzeln hochgeladen.
   - Die v1-Vorlagen aller fünf liegen in `ServerStorage.MeshyKit_v1`.
   - Die Rauheits-Map ist für alle Modelle dieselbe ID.

Messung (27.11.2026): Studio, Device Simulator Galaxy A06, Edit-Modus, 12 Truhen, abwechselnd v2, v1 und keine Truhe.
- Bei 60 FPS (Studio-Obergrenze) sinkt die Bildrate in keinem Fall.
- Nahansicht: GPU-Zeit pro Frame v2 etwa 15,0 ms, v1 etwa 14,2 ms, ohne Truhe etwa 13,6 ms.
- Fernansicht: Die Werte streuen zu stark für eine Aussage.
- Mit allen fünf Modellen (38 Stück, v2 gegen v1 im Wechsel): Die Bildrate liegt bei beiden zwischen 58 und 60 FPS. Die GPU-Zeit ist auf dem Plot 0,3 bis 0,7 ms höher. Die Hub-Messung zielte zwischen die Shops und hatte keinen im Bild; sie zählt nicht. Place-Version 686.
- Der Simulator rechnet auf dem PC. Was ein echtes Handy schafft, zeigt nur ein Test dort.

## Werte

| Modell | Größe in Studs (B × T × H) | Dreiecke | Maps |
|---|---|---|---|
| ScoopChest | 14,0 × 7,1 × 6,9 | 4.200 + Deckel 1.600 | 1024 |
| SellCart | 19,5 × 7,6 × 13,6 | 10.000 | 1024 |
| CraftingStation | 26,7 × 12,0 × 18,0 | 12.000 | 1024 |
| UpgradeShop | 22,7 × 18,9 × 19,0 | 14.000 | 2048 |
| CosmeticShop | 24,2 × 18,9 × 25,5 | 14.000 | 2048 |

- **LODs:** Roblox hat für MeshParts keine eigenen LOD-Stufen. Es rechnet sie selbst (`RenderFidelity = Automatic`).
- **Kollision:** eine Box pro Modell über alles, was unter einer Höhengrenze liegt (`collide` in `build.py`). Die Meshes selbst kollidieren nicht und werden nicht abgefragt.
- **Truhe:** Der Deckel öffnet um 53°, so weit wie er im Meshy-Modell offen steht (`Config/Chest.lid.angle`). Die Attachments `ScoopSlot1` bis `ScoopSlot6` sitzen 0,6 Studs unter der Kuppe der modellierten Kugel in jedem Becher, nummeriert von links aus Spielersicht.
- **Schilder:**
  - UPGRADES und CRAFTING sind im Meshy-Modell aufgemalt, dort steht kein Text darüber.
  - SELL steht auf dem leeren Schild unter der Theke.
  - Der Cosmetic-Shop hat kein Schild, COSMETICS steht deshalb auf der Markise.
  - Der Quest Hub (v2) hat nur das aufgemalte Emblem, QUESTS steht deshalb auf der Vorderkante der Markise.
- **Vorschauen:** vorher und nachher je Modell im Vault unter `Shop Kit Vorschau/Meshy`.
