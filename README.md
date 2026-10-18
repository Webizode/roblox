# Wobble Scoops

Roblox-Spiel: Eiskugeln fangen, einen wackelnden Turm mit dem Daumen balancieren und ihn zum eigenen Eiswagen tragen, bevor er kippt. Volles Konzept in [`docs/concept.md`](docs/concept.md), der Kill-Test für Woche 1 in [`docs/killtest.md`](docs/killtest.md).

**Stand:** Woche 1, Feel-Prototyp. Big Swirl schießt Kugeln, Fangen, Wackelturm mit 3 Steuervarianten (A Joystick, B Balance-Pad, C Gyro), Servieren am Wagen, Coins, Kill-Test-Log. Rempeln, Greg, Golden Scoops, Speichern und Shop kommen ab Woche 2.

## Setup auf Windows (einmalig, ca. 1 Abend)

1. **Roblox Studio** installieren und einloggen: <https://create.roblox.com>
2. **Claude Code** installieren (Desktop-App oder CLI).
3. **Studio-MCP verbinden:** In Studio *Assistant* öffnen → `…` → *Manage MCP Servers* → *Enable Studio as MCP server* einschalten → unter *Quick connect* Claude Code aktivieren → Studio und Claude neu starten. Der grüne Punkt in *Manage MCP Servers* zeigt die Verbindung.
   Fallback per CLI: `claude mcp add Roblox_Studio -- cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat`
4. **Git** installieren und das Repo klonen.
5. **Rokit** (Toolchain-Manager) in PowerShell installieren:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
6. PowerShell schließen, neu öffnen (nicht die ISE, nicht als Administrator) und **im Repo-Ordner**:
   ```powershell
   cd $HOME\Documents\roblox
   rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
   rokit install          # Rojo, StyLua, Selene, Lune in den Versionen aus rokit.toml
   rojo plugin install    # Rojo-Plugin für Studio
   ```

## Spielen und testen

**Rojo starten:** im Repo-Ordner `start-rojo.cmd` doppelklicken. Das Skript wechselt selbst in den richtigen Ordner, installiert fehlende Tools und startet den Server. Oder in PowerShell:

```powershell
cd $HOME\Documents\roblox
rojo serve default.project.json
```

Das Fenster offen lassen. In Studio eine neue *Baseplate* öffnen → Plugins → Rojo → *Connect*. Dann **Play (F5)**: Der Server baut beim Start automatisch einen Graybox-Pier, wenn im Place noch keiner existiert.

- **Mehrspieler:** Test → *Clients and Servers* → 2–3 Spieler → Start.
- **Handy:** Test → *Device* (Emulator) und echtes Handy über eine privat veröffentlichte Version (File → Publish to Roblox).
- **Latenz:** Studio-Einstellungen → Network → *Incoming Replication Lag* auf 0,2 s, so fühlt sich ein typisches Handy an.
- **Steuerung am PC:** WASD laufen. Balancieren: auf das Pad unten rechts klicken und von dort gegen die Neigung ziehen, oder I/J/K/L. Tippen = kleiner Schubs, Halten = voller Schub. Der Punkt im Pad zeigt, wohin der Turm kippt.
- **Fangen:** Eine Kugel zählt, sobald sie den Turm irgendwo berührt, nicht nur die Spitze. Servieren passiert automatisch, wenn du mit dem Turm von draußen auf die gelbe Matte am eigenen Wagen läufst.
- **Kill-Test-Daten:** Die Ausgabe zeigt alle 2 Minuten `[KillTest] summary`, die Rohdaten liegen als JSON in `ServerStorage.KillTestLog`.
- **Fang-Diagnose:** Solange `debugCatch` in `src/shared/Config/Features.luau` an ist, schreibt der Server jeden abgelehnten Fang mit Grund in die Ausgabe (`[Catch] rejected …`).

## Probleme beim Start

| Meldung | Ursache | Lösung |
|---|---|---|
| `Failed to find tool 'rojo' in any project manifest file` | Rokit sucht `rokit.toml` nur im aktuellen Ordner und den Ordnern darüber. Das Fenster steht nicht im Repo-Ordner (neue PowerShell startet in `C:\Users\<Name>`, als Admin in `C:\WINDOWS\system32`). | `cd $HOME\Documents\roblox`, dann erneut. Oder `start-rojo.cmd` doppelklicken. **Nicht** `rokit add` ausführen, das trägt Tools in eine andere Datei ein. |
| `Installed and created links for 0 tools` | `rokit install` lief außerhalb des Repo-Ordners. | Im Repo-Ordner wiederholen. |
| `The following tool has not been marked as trusted` | Die Vertrauens-Abfrage von `rokit install` funktioniert nicht in der PowerShell ISE. | `rokit trust …` aus Setup-Schritt 6 ausführen, dann `rokit install`. |
| `rojo` / `rokit` wird nicht erkannt | Rokit fehlt oder das Fenster war schon vor der Installation offen. | Setup-Schritt 5, danach ein neues Fenster öffnen. |

Prüfen, ob du im richtigen Ordner bist: `Test-Path .\rokit.toml` muss `True` ausgeben.

## Checks (vor jedem Push)

```powershell
lune run scripts/check
```

Führt StyLua, Selene, die Lune-Tests, einen Rojo-Build und die Prüfung des gebauten Place aus.

## Struktur

| Pfad | Wird in Roblox zu | Inhalt |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | reine Logik (TowerModel, TowerShape, Economy, Recipes, ShotMath), Remotes, `Config/*` |
| `src/server` | `ServerScriptService.Server` | Services: Graybox, Cart, Tower, Launcher, KillTestLog |
| `src/client` | `StarterPlayerScripts.Client` | TowerVisual, Sfx, Controllers: Hud, BalancePad, TowerController, ShotRenderer, RemoteTowers, VariantSwitcher |
| `tests` | (nur Lune) | Unit-Tests der reinen Logik, Syntax-Check aller Dateien, Place-Check |
| `docs` | | Konzept, Kill-Test |
