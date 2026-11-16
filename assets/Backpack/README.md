# Waffel-Rucksack

Die Waffel auf dem Rücken jedes Spielers, seit dem Kill-Test vom 13.11.2026 aus Blender: Kegel mit erhabenem Waffelgitter, runder Schoko-Rand, darunter eine Glasur mit Tropfen in der Sortenfarbe des eigenen Plots (Plot 01 Mint, 02 Mango usw., `Config/Palette.plotFlavors`). Maße wie die alte Waffel (`Config/Backpack`), die Turmkugeln sitzen also wie bisher darin. Etwa 3.700 Dreiecke.

- `build_backpack.py`: baut in Blender die Szene `BackpackKit` und schreibt `Backpack_Waffle.fbx` nach `C:\Users\Wobble\Desktop\roblox-assets\Backpack`. Gibt Größe und Mitte jedes Meshes aus, die stehen in `Config/Backpack.meshes`.
- `Backpack.blend`: die Szene (dazu die Vorschau `WaffelVorschau`).
- `studio_backpack_templates.luau`: macht nach dem Import die Vorlagen in `ReplicatedStorage.BackpackKit`.
- Vorschau: Vault `UI Vorschau`, „Waffel Vorschau alt und neu 2026-11-14“ und „Waffel Export Mint 2026-11-14“.

Solange `ReplicatedStorage.BackpackKit` fehlt, zeichnet der Client die alte Waffel aus gestuften Zylindern.

## Import in Studio (Klicks)

1. Studio mit dem Place öffnen, Edit-Modus (kein Playtest).
2. **Datei → 3D importieren** (File → Import 3D), im Dateidialog `C:\Users\Wobble\Desktop\roblox-assets\Backpack\Backpack_Waffle.fbx` wählen, **Öffnen**.
3. Im Importfenster: Meshes **nicht zusammenführen** (vier MeshParts: Waffle, Lines, Rim, Glaze), „In Workspace einfügen“ angehakt, Einheit Studs, Größe 1:1, **Importieren**. Das Modell heißt `Backpack_Waffle`.
4. **Ansicht → Befehlsleiste** (View → Command Bar), den ganzen Inhalt von `assets/Backpack/studio_backpack_templates.luau` hineinkopieren, **Enter**. Die Ausgabe meldet „4 meshes in ReplicatedStorage.BackpackKit“.
5. **Datei → Speichern** (Strg+S).
6. Playtest: Die Waffel auf dem Rücken hat Gitter, Schoko-Rand und Glasur in der Farbe des eigenen Plots.

Ändert sich das Mesh in Blender, `build_backpack.py` erneut laufen lassen, die ausgegebenen Werte in `Config/Backpack.meshes` übernehmen und Schritte 2 bis 5 wiederholen.
