# Wobble Scoops

Roblox-Spiel: Eiskugeln fangen, einen wackelnden Turm mit dem Daumen balancieren und ihn zum eigenen Eiswagen tragen, bevor er kippt. Volles Konzept in [`docs/concept.md`](docs/concept.md), der Kill-Test für Woche 1 in [`docs/killtest.md`](docs/killtest.md).

**Stand:** Woche 1, Feel-Prototyp. Big Swirl schießt Kugeln, Fangen, Wackelturm mit automatisch gewählter Steuerung (Tasten am PC, Neigen am Handy, sonst Laufen; Balance-Pad optional in den Einstellungen), Servieren am Wagen, Coins, Kill-Test-Log. Rempeln, Greg, Golden Scoops, Speichern und Shop kommen ab Woche 2.

## Setup auf Windows (einmalig, ca. 1 Abend)

1. **Roblox Studio** installieren und einloggen: <https://create.roblox.com>
2. **Claude Code** installieren (Desktop-App oder CLI).
3. **Studio-MCP verbinden:** In Studio *Assistant* öffnen → `…` → *Manage MCP Servers* → *Enable Studio as MCP server* einschalten → unter *Quick connect* Claude Code aktivieren → Studio und Claude neu starten. Der grüne Punkt in *Manage MCP Servers* zeigt die Verbindung.
   Für Claude Code ist das schon im Repo eingerichtet: `.mcp.json` enthält die Studio-Konfiguration. Startest du Claude Code im Repo-Ordner, fragt es einmal, ob es den Server `Roblox_Studio` nutzen darf, dann zustimmen.
   Fallback per CLI (der Befehl, den Studio für Claude Code anzeigt, mit `--scope user`, damit er in jedem Ordner gilt):
   `claude mcp add --scope user --transport stdio Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"`
4. **Git** installieren und das Repo nach `Dokumente\roblox` klonen (normale PowerShell, nicht die ISE, nicht als Administrator):
   ```powershell
   cd $HOME\Documents
   git clone -b claude/wobble-scoops-week1 https://github.com/Webizode/roblox.git roblox
   ```
5. **Rokit** (Toolchain-Manager) in PowerShell installieren:
   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```
6. Im selben Fenster weiter, **im Repo-Ordner**:
   ```powershell
   $env:Path = "$HOME\.rokit\bin;$env:Path"   # Rokit sofort nutzbar, ohne neu anzumelden
   cd $HOME\Documents\roblox
   rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene lune-org/lune
   rokit install          # Rojo, StyLua, Selene, Lune in den Versionen aus rokit.toml
   rojo plugin install    # Rojo-Plugin für Studio
   ```

## Spielen und testen

**Rojo starten:** im Repo-Ordner `start-rojo.cmd` doppelklicken. Das Skript wechselt selbst in den richtigen Ordner, installiert fehlende Tools und das Studio-Plugin und startet den Server. Oder in einer normalen PowerShell (nicht in der ISE):

```powershell
cd $HOME\Documents\roblox
rojo serve default.project.json
```

Das Fenster offen lassen. In Studio eine neue *Baseplate* öffnen → Plugins → Rojo → *Connect*. Dann **Play (F5)**: Der Server baut beim Start automatisch einen Graybox-Pier, wenn im Place noch keiner existiert.

- **Mehrspieler:** Test → *Clients and Servers* → 2–3 Spieler → Start.
- **Handy:** Test → *Device* (Emulator) und echtes Handy über eine privat veröffentlichte Version (File → Publish to Roblox).
- **Latenz:** Studio-Einstellungen → Network → *Incoming Replication Lag* auf 0,2 s, so fühlt sich ein typisches Handy an.
- **Steuerung:** wird automatisch gewählt, es gibt keinen Umschalter im HUD.
  - **PC (Tastatur):** WASD laufen, I/J/K/L drücken den Turm gegen die Neigung. Tippen = kleiner Schubs, Halten = voller Schub. Beim ersten Turm zeigt ein Hinweis die Tasten.
  - **Handy mit Lagesensor:** Gerät gegen die Neigung kippen. Abschaltbar in den Einstellungen („Tilt controls“), dann wird durch Laufen balanciert.
  - **Handy ohne Sensor / Gamepad:** Balancieren durch Laufen in Richtung der Neigung.
  - **Balance-Pad:** nur, wenn es in den Einstellungen (Regler-Symbol unter den Coins) eingeschaltet ist. Auf das Pad klicken oder tippen und von dort gegen die Neigung ziehen; der Punkt im Pad zeigt, wohin der Turm kippt. Solange das Pad an ist, zählt nur das Pad (I/J/K/L sind dann aus), damit es keine doppelte Steuerung gibt.
- **HUD:** Coins und Einstellungen links, Turm-Karte (Kugeln, Wert, Steady-Bonus) unten Mitte mit höchstens einem Hinweis darüber, Balance-Anzeige rechts (am PC unten rechts, am Handy über dem Sprung-Button), solange du einen Turm trägst. Es gibt keine Wurf- oder Fang-Buttons: Die Big Swirl schießt von selbst, gefangen und serviert wird automatisch.
- **Fangen:** Eine Kugel zählt, sobald sie den Turm irgendwo berührt, nicht nur die Spitze. Servieren passiert automatisch, wenn du mit dem Turm von draußen auf die gelbe Matte am eigenen Wagen läufst.
- **Kill-Test-Daten:** Die Ausgabe zeigt alle 2 Minuten `[KillTest] summary`, die Rohdaten liegen als JSON in `ServerStorage.KillTestLog`.
- **Fang-Diagnose:** Solange `debugCatch` in `src/shared/Config/Features.luau` an ist, schreibt der Server jeden abgelehnten Fang mit Grund in die Ausgabe (`[Catch] rejected …`).

## Probleme beim Start

| Meldung | Ursache | Lösung |
|---|---|---|
| `Failed to find tool 'rojo' in any project manifest file` | Rokit sucht `rokit.toml` nur im aktuellen Ordner und den Ordnern darüber. Das Fenster steht nicht im Repo-Ordner (neue PowerShell startet in `C:\Users\<Name>`, als Admin in `C:\WINDOWS\system32`). | `cd $HOME\Documents\roblox`, dann erneut. Oder `start-rojo.cmd` doppelklicken. |
| `Installed and created links for 0 tools` | `rokit install` lief außerhalb des Repo-Ordners. | Im Repo-Ordner wiederholen. |
| `The following tool has not been marked as trusted` | Die Vertrauens-Abfrage von `rokit install` funktioniert nicht in der PowerShell ISE. | `rokit trust …` aus Setup-Schritt 6 ausführen, dann `rokit install`. |
| `rokit` wird nicht erkannt | Rokit trägt sich bei der Installation nur in die Registry ein. Neue Fenster sehen das erst nach dem nächsten Anmelden. | Im Fenster `$env:Path = "$HOME\.rokit\bin;$env:Path"` ausführen, oder `start-rojo.cmd` doppelklicken (das macht es selbst). Fehlt Rokit ganz: Setup-Schritt 5. |
| `rokit` geht, aber `rojo` wird nicht erkannt | Die Tools wurden noch nicht im Repo-Ordner installiert. | Im Repo-Ordner `rokit install`, oder `start-rojo.cmd` doppelklicken. |
| `Could not start the Rojo server on 127.0.0.1:34872` | Ein anderer Rojo-Server läuft schon (anderes Fenster, oder ein Start aus der ISE ohne sichtbares Fenster). | Das andere Fenster schließen oder im Task-Manager `rojo.exe` beenden. |

**Nicht** `rokit add`, `rokit init` oder `rokit add --global` ausführen, auch wenn Rokit das in einer Meldung vorschlägt: Rojo steht schon in der `rokit.toml` des Repos. Außerhalb des Repos bricht `rokit add` nur ab, und `rokit init` würde dort eine zweite `rokit.toml` anlegen, die das Projekt durcheinanderbringt.

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
| `src/client` | `StarterPlayerScripts.Client` | TowerVisual, Sfx, Ui (gemeinsamer UI-Stil), Controllers: Hud, Settings, BalancePad, TowerController, ShotRenderer, RemoteTowers |
| `tests` | (nur Lune) | Unit-Tests der reinen Logik, Syntax-Check aller Dateien, Place-Check |
| `docs` | | Konzept, Kill-Test |
