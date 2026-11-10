# Deco Kit

Deko Runde 2 (09.11.2026): Büsche, Bäume, Palmen, Steine und das Leaderboard-Schild für Hub-Ring und Plot-Inseln. Gebaut wie Plot Kit und Hub Kit, mit denselben Bausteinen und Farben: glänzender Cartoon-Stil, runde Kanten, Farbe als Variante, keine Texturen. Der Code des Hub Kits wird dafür wiederverwendet: `run_decokit.py` liest `hubkit.py` und die Bausteine sowie den Export-Teil von `build_hub_pack.py` mit umbenannten Namen (`HK_` → `DK_`, `HubKit` → `DecoKit`).

- Blender-Datei: `assets/DecoKit/DecoKit.blend`, je Modell eine Collection `DK_<Model>`
- Skripte:
  - `build_deco_pack.py` baut die Modelle.
  - `run_decokit.py` baut alles in einem Hintergrund-Blender.
  - `studio_decokit_templates.luau` macht in Studio Vorlagen aus dem Import. Die Datei wird erzeugt, Änderungen gehören in `build_deco_pack.py`.
- FBX: `assets/DecoKit/fbx/DecoKit_<Model>.fbx` (nicht im Repo)
- Vorschauen: nur im Vault unter `Wobble Scoops\Deko Kit Vorschau`
- Maße und Daten: `decokit_models.json`
- Flackern geprüft mit `assets/find_zfighting.py -- DK_`: alle 14 Modelle sauber

Neu bauen:
```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python assets/DecoKit/run_decokit.py -- BushRound PalmBent
```

## Modelle

Maße in Studs (Breite × Tiefe × Höhe), Pivot unten mittig, Vorderseite −Z in Roblox.

| Modell | Maße | Dreiecke | Kollision | Referenz |
|---|---|---|---|---|
| BushRound | 7,0 × 6,6 × 4,8 | 2.464 | keine | Hecken und Blütenbüsche (1) |
| BushFlower | 6,9 × 6,5 × 4,8 | 3.904 | keine | Hecken und Blütenbüsche (2) |
| Hedge | 10,5 × 5,0 × 3,2 | 2.876 | keine | Hecken und Blütenbüsche (3) |
| BushSmall | 3,6 × 3,7 × 1,6 | 696 | keine | Hecken und Blütenbüsche (4) |
| TreeRound | 8,9 × 8,5 × 13,5 | 1.696 | Box um den Stamm | frei |
| TreeTall | 4,4 × 4,5 × 18,8 | 1.148 | Box um den Stamm | frei |
| LollipopTree | 7,0 × 2,7 × 14,1 | 2.940 | Box um den Stiel | frei |
| IceTreeUpright | 8,3 × 8,3 × 16,6 | 4.136 | Box um den Stamm | Glänzender blauer Eiskrembaum; Varianten Mint und Lemon (Teile Crown und Crown2) |
| PalmStraight | 11,1 × 11,2 × 13,3 | 4.652 | Box um den unteren Stamm | Zwei Palmen (links) |
| PalmBent | 11,4 × 11,0 × 12,9 | 4.652 | Box um den unteren Stamm | Zwei Palmen (rechts) |
| RockRound | 6,3 × 3,4 × 3,7 | 876 | keine | Felsen mit grünen Blättern (1) |
| RockFlat | 6,2 × 4,1 × 1,5 | 700 | keine | Felsen mit grünen Blättern (2) |
| RockGroup | 4,6 × 2,3 × 1,7 | 840 | keine | Felsen mit grünen Blättern (3) |
| Leaderboard | 14,9 × 2,8 × 15,7 | 5.194 | Box über Pfosten und Tafel | Eiscreme-Leaderboard mit Waffelrahmen |

Am Leaderboard legt das Vorlagenskript zwei unsichtbare Teile an, beide mit der Front nach vorne: `Display` (8,3 × 6,7) vor der Schoko-Tafel für die Bestenliste und `Header` (8,8 × 1,2) vor dem Karamell-Brett für das Wort LEADERBOARD.

Noch nicht in Studio importiert. Den Import macht der Nutzer per Datei → 3D importieren, danach läuft `studio_decokit_templates.luau`, so wie beim Hub Kit (`assets/HubKit/README.md`).
