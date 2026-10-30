# Wobble Scoops

Roblox-Spiel, Solo-Projekt mit Claude Code. Ziel: ~2.000 € über DevEx. Referenz für alle Design-Fragen: `docs/design-regeln.md` (verbindlich, hat bei Widersprüchen Vorrang) und `docs/concept.md`. Aktueller Projektstand und Entscheidungen: `docs/projektstand.md`. Aktueller Stand und Kill-Test: `docs/killtest.md`. Mit dem Nutzer auf Deutsch sprechen.

## Workflow

- **Code lebt in Dateien** unter `src/` und wird per Rojo (`rojo serve`) live nach Studio gesynct. Scripts nie direkt in Studio ändern, Rojo überschreibt sie. Ablauf, Plugin-Einstellungen und Grenzen (laufender Playtest lädt Code nicht nach): `docs/live-sync.md`.
- **Die Map lebt im Place:** `Workspace."Ice Cream Map"` ist seit 30.10.2026 die Graybox für 12 Spieler: Arena r 0–135 (Boden y 1,2) mit 12 Plateaus und Deckung in `Covery`, ebener Streifen r 135–171 auf y 9 mit 12 eingelassenen Rampen (`Schody`, 12 breit, Oberkante r 159, mit Grenzlinie in `Strefa`), Hub-Ring r 171–232 als leere Fläche, 12 Brücken 18 × 60 (`Mosty`, r 232–292) zu 12 Plot-Inseln 70 × 70 (`Plots/Plot_01` bis `Plot_12`, Mitte r 327, Plot-Fläche 64 × 64). Insel, Brücke, Streifen und Rampe liegen je auf einer Linie bei 15° + k·30°. Die Arena-Zone (Boden plus Rampen bis zur Oberkante, keine Hysterese) steht in `Config/Map.arena` und wird von `ArenaZone` geprüft, auf Server und Client gleich: nur dort fliegen Kugeln und treffen Eisbälle; außerhalb zeigen Teleport-Buttons und „SAFE ZONE“ (ArenaService, TeleportMenu). Deckung, Plateaus, Rampen und Arenarand sind abgerundete MeshParts aus dem Baukasten `assets/IceKit` (Vorrat in `ServerStorage.IceKit`), nur Optik ohne Kollision und Abfragen; darunter liegen unsichtbare Quader und Keile (`*_Kolizja`, beim Rand die alten `Pas`-Blöcke) als Kollision, damit Landepunkte, Würfe und Wegfindung exakt bleiben. `CollisionFidelity` lässt sich per MCP-Script nicht setzen. Sie wird nur auf ausdrücklichen Auftrag geändert, vorher kommt eine Sicherheitskopie nach ServerStorage. Kornels Original-Insel (6 Stände) liegt unverändert in `ServerStorage."MapBackup_2026-10-30_6Staende"`, ältere Grayboxen daneben. Dazu kommen unsichtbare Hilfsteile in `Workspace.Pier` (`Plots.Plot_01` bis `Plot_12`, dauerhaft gestreamt, mit ServePoint am Brückenkopf der Insel r 298, Spawn in der Inselmitte, ArenaEntry 3 Studs hinter der eigenen Rampenkante r 162) und Terrain-Wasser bis y=-6. Sie muss dem Map-Vertrag oben in `src/server/Services/MapService.luau` folgen, sonst bricht der Server mit Fehler ab. Die Big Swirl baut `MapService` beim Start auf `Plac.Arena_Znacznik`. Ordnernamen und Regeln (Landezonen, Würfe, Wasser) stehen in `Config/Map.luau`.
- **Studio-MCP** (nur lokal auf Windows/Mac) ist für Playtests da: Play starten, Konsole auf Fehler prüfen, Screenshots, Spieler steuern, Map bauen, `ServerStorage.KillTestLog` lesen.
- Vor jedem Commit: `lune run scripts/check` (StyLua, Selene, Lune-Tests, Rojo-Build, Place-Check). Muss grün sein.

## Architektur-Regeln

- **Server ist die Wahrheit** über Kugeln, Fänge, Coins und Serve-Wert. Der Client simuliert nur die Neigung und meldet Stürze und einen Steady-Bonus, der serverseitig auf die Tragezeit gedeckelt wird.
- Jeder `OnServerEvent`-Handler prüft Typen (inkl. NaN/inf), Wertebereiche und Rate-Limits. Clientwerten nie vertrauen.
- `src/shared/*.luau` (TowerModel, TowerShape, Economy, Recipes, ShotMath) sind **rein**: keine Roblox-Globals, keine `require`s. Configs werden als Argument übergeben. Nur so laufen sie in Lune-Tests. Neue Logik mit Zahlen gehört hierher, mit Tests in `tests/`. Ausnahmen, die die Roblox-Laufzeit brauchen: `Remotes` und `MapQuery` (Raycasts auf die Map, die Regeln dazu stehen rein in `MapRules`).
- `src/shared/Config/*.luau` sind reine Daten. Tuning gehört dorthin, nicht in den Code.
- Services und Controller folgen demselben Muster: Modul mit optionalem `Init(registry)` und `Start()`, Reihenfolge in `init.server.luau` / `init.client.luau`.
- Features der späteren Wochen hängen an `Config/Features.luau`.
- **Monetarisierung:** keine Paid Random Items (keine Lootboxen, keine gekauften Glücks-Boosts), keine Kauf-Pop-ups beim Join, nichts, was anderen Spielern schadet (Pay-to-Grief). Siehe Monetarisierung in `docs/concept.md`.

## Konventionen

- Luau, Tabs, StyLua-Config im Repo. Code und Kommentare auf Englisch, Doku auf Deutsch.
- UI-Texte auf Englisch (Roblox übersetzt automatisch).
- Rojo 7.7: `init.server.luau` → Script, `init.client.luau` → LocalScript, Ordner ohne `init` → Folder.

## Befehle

```
rokit install                       # Toolchain aus rokit.toml (nur im Repo-Ordner, Rokit sucht rokit.toml von dort aufwärts)
rojo serve default.project.json     # Live-Sync nach Studio; unter Windows reicht ein Doppelklick auf start-rojo.cmd
lune run scripts/check              # alle Checks
lune run tests/run.luau             # nur Unit-Tests + Syntax-Check
stylua src tests scripts            # formatieren
```

## Cloud-Sessions

Dort gibt es kein Studio und kein MCP, nur Code schreiben und testen. GitHub-Release-Downloads (und damit Rokit) sind in Cloud-Sessions gesperrt: Tools mit `cargo install stylua --features luau`, `cargo install selene lune rojo` bauen. Selene braucht `roblox.yml` (aus der Roblox-API generiert, gitignored); lokal erzeugt Selene sie beim ersten Lauf selbst.
