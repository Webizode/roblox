# Wobble Scoops

Roblox-Spiel, Solo-Projekt mit Claude Code. Ziel: ~2.000 € über DevEx. Referenz für alle Design-Fragen: `docs/concept.md`. Aktueller Stand und Kill-Test: `docs/killtest.md`. Mit dem Nutzer auf Deutsch sprechen.

## Workflow

- **Code lebt in Dateien** unter `src/` und wird per Rojo (`rojo serve`) live nach Studio gesynct. Scripts nie direkt in Studio ändern, Rojo überschreibt sie.
- **Die Map lebt im Place** (`Workspace.Pier`). Sie wird in Studio gebaut (per Studio-MCP oder von Hand) und muss dem Map-Vertrag oben in `src/server/Services/GrayboxService.luau` folgen. Fehlt `Workspace.Pier`, baut der Server eine Graybox.
- **Studio-MCP** (nur lokal auf Windows/Mac) ist für Playtests da: Play starten, Konsole auf Fehler prüfen, Screenshots, Spieler steuern, Map bauen, `ServerStorage.KillTestLog` lesen.
- Vor jedem Commit: `lune run scripts/check` (StyLua, Selene, Lune-Tests, Rojo-Build, Place-Check). Muss grün sein.

## Architektur-Regeln

- **Server ist die Wahrheit** über Kugeln, Fänge, Coins und Serve-Wert. Der Client simuliert nur die Neigung und meldet Stürze und einen Steady-Bonus, der serverseitig auf die Tragezeit gedeckelt wird.
- Jeder `OnServerEvent`-Handler prüft Typen (inkl. NaN/inf), Wertebereiche und Rate-Limits. Clientwerten nie vertrauen.
- `src/shared/*.luau` (TowerModel, TowerShape, Economy, Recipes, ShotMath) sind **rein**: keine Roblox-Globals, keine `require`s. Configs werden als Argument übergeben. Nur so laufen sie in Lune-Tests. Neue Logik mit Zahlen gehört hierher, mit Tests in `tests/`.
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
