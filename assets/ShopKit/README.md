# Shop Kit

Die drei Shop-Gebäude des Hubs (10.11.2026): Upgrade Shop, Cosmetic Shop und Quest Hub. Bisher nur die Optik, die Funktion kommt später. Die Referenzen im Vault (`Wooble scoops Map assets 1`) zeigen dieselbe Bude in drei Ausstattungen. Deshalb baut `build_shop_pack.py` ein gemeinsames Gerüst (`booth`), und jeder Shop bekommt seine Akzentfarbe, sein Emblem auf dem Schild und seine Requisiten. Die Pipeline ist die des Hub Kits: `run_shopkit.py` liest `hubkit.py` und die Bausteine von `build_hub_pack.py` mit umbenannten Namen (`HK_` → `SK_`, `HubKit` → `ShopKit`), wie beim DecoKit.

| Modell | Maße (B × T × H) | Dreiecke | Akzent | Requisiten |
|---|---|---|---|---|
| UpgradeShop | 25,0 × 18,9 × 26,8 | 18.032 | Mint | Zahnrad und Kegel, Gläser, Schraubenschlüssel, Amboss, Aufsteller mit Diagramm |
| CosmeticShop | 25,3 × 18,9 × 26,7 | 17.288 | Pink und Lavendel | Sterne, Köpfe mit Krone, Hasenohren und Hut, Geschenk, Eistüten, Standspiegel |
| QuestHub | 25,0 × 18,9 × 26,7 | 16.572 | Blau | Schriftrolle mit Ausrufezeichen, Rollen und Bücher, Pinnwand, Tintenfass mit Feder, Briefkasten, Kisten |

- **Grundfläche:** etwa 24 × 16 mit dem Sockel. Die Shop-Flächen im Hub sind 44 × 30 (`Dekoracje.Hub.Platzhalter`), davor bleibt also Platz für einen Vorplatz.
- **60/30/10:** Creme, Waffel und Holz tragen das Gebäude. Die Akzentfarbe steht nur an Markise, Schild, Fahnen, Fensterrahmen, Tresentuch, NPC-Teppich und den Streifen am Sockel.
- **Kollision:** eine Box über das Gebäude, eine über den Sockel und je eine für Aufsteller, Spiegel, Briefkasten und Kisten.
- **Unsichtbare Teile** (legt `studio_shopkit_templates.luau` an):
  - `NameField` auf dem cremefarbenen Namensfeld des Schilds, 7 × 2,2, Front nach vorne, für das SurfaceGui mit dem Namen. Im Modell steht kein Text.
  - `NpcSpot` auf dem freien Boden hinter dem Tresen, auf dem Teppich, für den NPC.
- **Flackern:** `assets/find_zfighting.py -- SK_` meldet für alle drei nichts.
- **Vorschauen:** nur im Vault unter `Wobble Scoops\Shop Kit Vorschau`. Die FBX-Dateien in `assets/ShopKit/fbx` sind nicht im Repo.

Neu bauen:
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/ShopKit/run_shopkit.py -- UpgradeShop
```

In Studio importiert und gesetzt am 10.11.2026: `studio_shopkit_templates.luau` macht die Vorlagen, `studio_shopkit_place.luau` setzt die Gebäude auf die Shop-Flächen und schreibt die Namen.
